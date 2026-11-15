#!/usr/bin/env python3
"""Compile real Fennel and exercise OS-mocked dark-mode recovery (stdlib only)."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, help="keep generated Lua, logs and results.json here")
    parser.add_argument("--lua", default=os.environ.get("LUA", "lua"))
    parser.add_argument("--luac", default=os.environ.get("LUAC", "luac"))
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    tests = root / "tests"
    for command in (args.lua, args.luac):
        if shutil.which(command) is None:
            parser.error(f"required executable not found: {command}")
    scratch = None
    if args.output_dir:
        out = args.output_dir.expanduser().resolve()
        out.mkdir(parents=True, exist_ok=True)
    else:
        scratch = tempfile.TemporaryDirectory(prefix="dark-mode-tests-", dir=os.environ.get("TMPDIR"))
        out = Path(scratch.name)
    started = time.monotonic()
    results = {"mode": "mocked-OS-only", "checks": 0, "passed": 0, "failed": 0, "suites": [], "source_sha256": {}}

    def run(command: list[str], name: str, timezone: str | None = None) -> str:
        env = os.environ.copy()
        if timezone:
            env["TZ"] = timezone
        process = subprocess.run(command, cwd=root, env=env, text=True, stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT, timeout=240, check=False)
        (out / f"{name}.txt").write_text(process.stdout)
        if process.returncode != 0:
            raise RuntimeError(f"{name} exited {process.returncode}:\n{process.stdout}")
        return process.stdout

    try:
        results["lua_version"] = run([args.lua, "-v"], "lua-version").strip()
        results["luac_version"] = run([args.luac, "-v"], "luac-version").strip()
        results["fennel_version"] = run([args.lua, str(root / "fennel.lua"), "--version"], "fennel-version").strip()
        generated = {}
        for name in ("auto-dark-mode", "auto-dark-mode-location", "init-fennel"):
            source = root / f"{name}.fnl"
            dest = out / f"{name}.lua"
            # Separate stdout from stderr: compiler diagnostics must never become executable Lua.
            process = subprocess.run([args.lua, str(root / "fennel.lua"), "--compile", str(source)],
                                     cwd=root, text=True, capture_output=True, timeout=60, check=False)
            (out / f"{name}-compile.txt").write_text(process.stderr)
            if process.returncode != 0:
                raise RuntimeError(f"Fennel compilation failed for {name}: {process.stderr}")
            dest.write_text(process.stdout)
            generated[name] = str(dest)
            results["source_sha256"][source.name] = hashlib.sha256(source.read_bytes()).hexdigest()
        lua_files = [root / "init.lua", *(Path(p) for p in generated.values()), *sorted(tests.glob("*dark-mode*.lua"))]
        for index, path in enumerate(lua_files):
            run([args.luac, "-p", str(path)], f"syntax-{index}")
        results["syntax_files"] = len(lua_files)
        results["syntax"] = "passed"
        configurations = [
            ("location", "auto-dark-mode-location-test.lua", [generated["auto-dark-mode-location"]], "UTC"),
            ("entry", "auto-dark-mode-entry-test.lua", [generated["init-fennel"]], "UTC"),
            ("integration", "auto-dark-mode-integration-test.lua", [generated["auto-dark-mode"], generated["auto-dark-mode-location"], generated["init-fennel"]], "UTC"),
        ]
        zones = ("UTC", "America/Chicago", "Asia/Kathmandu", "Australia/Adelaide", "Pacific/Auckland")
        for zone in zones:
            configurations.append(("scheduler-" + zone.replace("/", "-"), "auto-dark-mode-scheduler-test.lua", [generated["auto-dark-mode"]], zone))
        for name, script, inputs, zone in configurations:
            output = run([args.lua, str(tests / script), *inputs], name, zone)
            # Both upstream unit suites expose explicit summaries; don't infer success from exit alone.
            summary = re.search(r"(?m)^(?:Scheduler|Entry|Integration): (\d+) passed, (\d+) failed, (\d+) checks$", output)
            if summary:
                passed, failed, checks = map(int, summary.groups())
            else:
                summary = re.search(r"(?m)^(\d+) checks: (\d+) passed, (\d+) failed$", output)
                if not summary:
                    raise RuntimeError(f"{name}: missing test summary")
                checks, passed, failed = map(int, summary.groups())
            pass_lines = len(re.findall(r"(?m)^PASS ", output))
            fail_lines = len(re.findall(r"(?m)^FAIL ", output))
            if checks != passed + failed or passed != pass_lines or failed != fail_lines or failed:
                raise RuntimeError(f"{name}: inconsistent/failing enumerated test count")
            results["suites"].append({"name": name, "timezone": zone, "checks": checks, "passed": passed, "failed": failed})
            for key in ("checks", "passed", "failed"):
                results[key] += {"checks": checks, "passed": passed, "failed": failed}[key]
            print(f"{name}: {passed}/{checks} passed")
        for source in sorted(tests.glob("*dark-mode*")):
            if source.is_file():
                results["source_sha256"]["tests/" + source.name] = hashlib.sha256(source.read_bytes()).hexdigest()
        results["success"] = True
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        results["success"] = False
        results["error"] = str(error)
        print(error, file=sys.stderr)
    finally:
        results["duration_seconds"] = round(time.monotonic() - started, 3)
        (out / "results.json").write_text(json.dumps(results, indent=2) + "\n")
        print(f"Total: {results['passed']}/{results['checks']} mocked checks; syntax {results.get('syntax', 'failed')}")
        if args.output_dir:
            print(f"Evidence: {out}")
        if scratch:
            scratch.cleanup()
    return 0 if results["success"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
