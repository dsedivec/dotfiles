# Solar dark-mode recovery

## Deployment and compatibility

The live configuration still loads `init.lua` → the bundled Fennel searcher →
`init-fennel.fnl`; no generated Lua is installed in `~/.hammerspoon`.
`init-fennel.fnl` retains `auto-dark-mode.start(true)` (solar/manual mode even on
modern macOS), the existing console/Emacs/iTerm theme hook and initial hook sync,
and its existing exported `adm` controls. A chained `hs.shutdownCallback` stops
the automation on reload/quit before calling any previously installed handler;
a cleanup exception cannot prevent that previous handler from running. This is
synchronous cleanup, not work deferred until after shutdown.[1]

This installation uses per-file symlinks into the dotfiles repository. The new
live dependency is:

```text
~/.hammerspoon/auto-dark-mode-location.fnl
  -> ../repositories/dotfiles/common/.hammerspoon/auto-dark-mode-location.fnl
```

The existing scheduler and entry-point symlinks remain in place. Installing the
files is not the same as reloading the running Hammerspoon Lua environment.

## Location fallback order

Sunrise and sunset are calculated **locally** with `hs.location.sunrise` and
`hs.location.sunset`; IP services supply coordinates, not solar times.[3]

One asynchronous attempt tries, in order:

1. **Core Location**, only when services are enabled and authorization reports
   `authorized`. A cached fix must have finite, in-range coordinates, nonnegative
   horizontal accuracy and an observation timestamp at most 24 hours old (with
   up to 60 seconds of future-clock tolerance). Otherwise an owned tracker waits
   up to **2 seconds** for a valid fix, then is detached and stopped. Denied,
   restricted, undefined or unavailable authorization skips native acquisition;
   the automation does not deliberately initiate a permission prompt. The native
   API distinguishes these authorization states.[3]
2. **IPinfo** using its JSON `loc` field.
3. **IPWhois (`ipwho.is`)** using `success`, `latitude` and `longitude`.
4. The scheduler continues from its validated **last-known location/cache** when
   the entire live attempt fails.

HTTP uses nonblocking `hs.task` with `/usr/bin/curl` argument arrays, not a shell
or synchronous HTTP call. Each provider has a **3-second connect** and
**8-second total/source** bound; an independent **20-second whole-attempt** timer
also completes/cancels the attempt. Response bodies are capped at **16 KiB**,
TLS verification is enabled, only HTTPS is allowed, curl user config is disabled,
and redirects are not followed. Native fixes, JSON shapes, HTTP statuses,
coordinate ranges and timestamps are validated before the scheduler sees them.
Late/canceled source callbacks cannot replace a newer source's result.

IP services necessarily see the connection's public egress IP. VPNs/proxies can
therefore produce an approximate or wrong location. Cached or IP fixes cannot
account for travel the computer has not observed. A valid native cached fix may
be used without making an IP request; `source` identifies the actual choice.

## Persistent cache and stale-data policy

The versioned **`auto-dark-mode.state.v1`** key is stored with `hs.settings`.
Hammerspoon documents this API as persistence across application launches.[2]
On this installation the preference domain is `org.hammerspoon.Hammerspoon`
(the installed bundle identifier), normally backed by:

```text
~/Library/Preferences/org.hammerspoon.Hammerspoon.plist
```

Use the settings API, not direct plist edits; macOS manages the preferences.
`hs.settings.bundleID` identifies the preference domain for a different build.[2]
There is no new JSON file and no iCloud dependency.

The record contains version, validated coordinates/source, acquisition and
observation times, last live success, and the most recently calculated local
solar date/zone/offset/sunrise/sunset. It is **not encrypted secret storage** and
contains sensitive location data. Do not print, attach or share the record or
an unrestricted preferences dump.

- At startup, cached coordinates immediately **recompute today's events** before
  live acquisition finishes. A fix older than **24 hours** is labeled `stale`;
  it is retained indefinitely as an explicitly approximate offline fallback.
  Today's appearance and next transition continue to advance during an outage.
- Previously saved absolute solar events are a secondary fallback only if local
  calculation fails and the **local date, zone and UTC offset still match**,
  including the current offset before a DST change. Yesterday's absolute times
  are never reused as today's events.
- Malformed independent fields are ignored; valid coordinates can survive bad
  solar metadata. Unsupported/malformed records and settings read/write failures
  cannot destroy an already usable in-memory schedule.
- If there are no valid coordinates and no usable same-day events, or solar
  calculation produces invalid/polar results, **preserve the existing system
  appearance** and retry. Do not invent sunrise/sunset or loop immediate timers.
- A successful live result replaces the approximate location, recalculates the
  current appearance and next transition, saves the record and clears retries.

To intentionally discard cached location, run this in Hammerspoon's console
only when you accept losing the offline fallback:

```lua
init_fennel.adm.stop()
hs.settings.clear('auto-dark-mode.state.v1')
hs.reload()
```

A reload is necessary to discard this module's already-loaded memory as well.

## Refresh, retry and lifecycle behavior

- A healthy local date change triggers a live refresh; there is also a 24-hour
  monotonic refresh bound. Each solar transition recalculates its successor
  locally instead of relying on a fetch made once per boot.
- A **60-second watchdog** detects date/zone/offset changes, clock jumps and
  missing/expired transition timers. Healthy minute checks do not perform
  network work or repeatedly query AppleScript appearance.
- Failed attempts retry after **30 seconds, 2 minutes, 10 minutes, 30 minutes,
  then every hour indefinitely**, measured after the preceding attempt fails.
  Watchdog, midnight and wake events respect an existing retry backoff.
- Wake immediately reconciles missed solar changes from cached coordinates and
  rebases relative timers; it requests one live refresh when backoff permits.
  The next watchdog tick does not repeat the same wake/clock-jump refresh.
- `update()` explicitly permits an immediate retry. Wake and manual callback
  clusters have a 2-second debounce; concurrent acquisitions coalesce.
- There is at most one scheduler acquisition, retry timer and solar-transition
  timer, plus the watchdog and owned wake/theme watchers. Acquisition briefly
  owns its own deadline/source timers and, at most, one curl task or tracker.
- `start(true)` is idempotent while active. `stop()` is unconditional/idempotent,
  including forced manual mode on modern macOS. Generation/request/timer tokens
  reject old callbacks after stop, restart or reload. Resources are installed
  before hooks run, and hook-triggered shutdown cannot reactivate scheduling.

Only acquisition is made asynchronous here. The user's existing appearance
AppleScript and `update_macos_theme.sh` hook are preserved, including their
synchronous execution. Mocked acquisition responsiveness does **not** establish
that those existing hooks, AppleScript permission dialogs or macOS itself can
never pause the UI. Their native latency remains a manual check.

## Inspecting failures without disclosing location

In the Hammerspoon console, after loading the new configuration:

```lua
hs.inspect(init_fennel.adm.status())
```

The returned scalar-only snapshot exposes:

| Field | Meaning |
| --- | --- |
| `active`, `manual` | Lifecycle and selected operating mode |
| `source` | `corelocation`, `ipinfo`, `ipwhois`, or `none` |
| `freshness` | `fresh`, `stale` (>24h observation age), or `missing` |
| `solarMode` | `calculated`, same-day `saved`, or `unavailable` |
| `failureCode` | `all-sources-failed`, `deadline-exceeded`, `acquisition-failed`, or absent |
| `failureCount` | Backoff stage, capped at 5; not a lifetime failure total |
| `cacheError` | `read-failed`, `invalid-cache`, `write-failed`, or absent |
| `inFlight` | An asynchronous location attempt is running |
| `retryScheduled`, `retryInSeconds` | Whether/when background retry is due |
| `transitionScheduled` | A future solar transition is installed |

The snapshot contains **no coordinates, IP addresses, raw errors or provider/
cache bodies**. A valid version-1 record with unusable individual fields can be
salvaged/ignored without `invalid-cache`; use `freshness`/`solarMode` as well.
The module does not log provider bodies or curl stderr. Native `hs.json.decode`
may emit a generic parse diagnostic for malformed object-shaped JSON; empty,
HTML and obviously truncated responses are screened first.

Inspect the next transition as a relative interval, without printing location:

```lua
local timer = init_fennel.adm['get-timer']()
print(timer and timer:nextTrigger() or 'no solar transition; inspect status')
```

Existing controls remain `init_fennel.adm.update()`, `.stop()`, `.start(true)`,
`['currently-dark?']()` and `['run-dark-mode-hooks']()`. A failed background
attempt leaves useful cached scheduling active; `retryScheduled=true` is not
itself a reason to restart Hammerspoon.

## Reproducible automated verification

From this `.hammerspoon` source directory, with Python 3, `lua` and `luac` on PATH:

```sh
python3 tests/run-dark-mode-tests.py
# Optional retained generated Lua, logs and machine-readable results:
python3 tests/run-dark-mode-tests.py --output-dir "$HOME/.cache/dark-mode-tests"
```

The stdlib-only runner uses the **bundled `fennel.lua` CLI**, compiles both real
production modules and the full real Fennel entry point, checks generated Lua,
`init.lua` and every Lua test/helper with `luac -p`, then runs:

- location unit suite: **86** scenario checks;
- full-entry shutdown/hook/control suite: **4** checks;
- real scheduler + real locator + full-entry integration: **19** checks;
- scheduler unit suite: **24** checks in each of UTC, America/Chicago,
  Asia/Kathmandu, Australia/Adelaide and Pacific/Auckland (**120** checks).

Verified on **November 15, 2026**: **229/229 passed**, Fennel **1.5.1**, standalone
Lua/luac **5.5.1**, all **9** Lua syntax checks passed. Results include source
hashes and enumerated count validation, not just process exit status.

| Requirement | Mocked evidence |
| --- | --- |
| Healthy startup/current appearance/next event | Unit + combined actual-entry integration |
| Offline startup, cache/no cache, later recovery | Unit + integration; verifies current appearance and exact next event after recovery |
| Denied native permissions; fractional fix timestamps | Location unit + cross-component integration |
| IPinfo timeout/alternate success, all hung sources | Location unit + integration with a separately firing responsiveness sentinel |
| Malformed provider/cache data, settings failure | Location/scheduler unit + integration |
| Stale saved dates; current-day coordinate recalculation | Scheduler unit + integration |
| Midnight, timezone, signed fractional offsets, DST | Five-zone scheduler unit + synthetic dynamic-zone integration |
| Sleep/wake, clock discontinuities | Scheduler unit + integration, including the following watchdog tick |
| Reload, cancellation, late callbacks, manual controls | Full-entry + integration; canceled callbacks deliberately invoked again |
| Multi-week uptime, no duplicate timers/request storms | **35 healthy days and 35 offline days** in scheduler tests per zone, plus combined-module integration; checks current/next state and bounded retries |

All tests use **synthetic** coordinates, provider fixtures, clocks, settings,
AppleScript, tasks, trackers, notifications and theme hooks. No real preference,
permission, appearance, network or iCloud operations are performed by the runner.
Solar fixtures test scheduling contracts, not astronomical accuracy. Simulated
module restarts share deep-copied mock preferences; they do not prove native
UserDefaults durability or Hammerspoon app-restart behavior.

## Native verification still required

The installed app is Hammerspoon **1.1.1**. A read-only CLI probe on November 15,
2026 exited **69** because its Hammerspoon message port was unavailable. IPC was
**not enabled**, permissions were not requested, real preferences were not
written, and the running configuration was **not reloaded** by this task.
Standalone Lua success is not a claim about the embedded runtime.

When convenient, verify locally (not while relying on unattended automation):

1. Reload using Hammerspoon's normal menu. Confirm existing hotkeys/window
   controls and theme hooks still load. Inspect only sanitized `status()` and
   the relative next transition. Confirm the actual current appearance and its
   next change agree with your location/date; check for permission/UI latency.
2. After one successful fix, quit/relaunch with networking unavailable. Confirm
   cached current-day calculation and a retry. Restore connectivity and confirm
   recovery without another reload. Separately test a first run with no cache
   only if you intentionally clear the cache as above.
3. Check authorized and denied Location Services states through macOS settings;
   verify no unexpected prompts. If authorization is reported `undefined`, the
   module intentionally uses IP fallback rather than forcing a prompt.
4. Sleep across a transition, then wake. Confirm appearance changes promptly,
   next transition is future, and retry/backoff behavior remains bounded.
5. If safe, test a real timezone/clock change and restore it afterwards. The
   mocked zones/DST checks do not change or validate actual system settings.
6. Reload once while a lookup is pending. Check no late old result changes the
   replacement schedule and no continuing old curl/tracker work remains.

**Upstream/native caveat:** Hammerspoon 1.1.1 task source inspection in the
location-component handoff identified that task userdata/pipes for a process
which **never launches** can remain pinned without a public disposal API. This
module detaches the failed-launch callback and does not terminate an unlaunched
NSTask, but cannot promise zero native retention for repeated OS process-launch
failures. Ordinary launched curl network failures/timeouts are bounded and
cleaned up in mocks; actual task-termination timing remains a native check. No
private `__gc` workaround is used. If zero retention under OS launch failure is
a release requirement, this caveat requires upstream/root disposition rather
than a claim that the mock suite proves it away.

A catastrophic native timer/cleanup exception can also prevent a locator
completion from reaching the scheduler; its normal recovery relies on the
locator's independent deadline callbacks being delivered. The tests do not
claim recovery when the event loop/cleanup APIs themselves stop functioning.

## Sources

[1] https://www.hammerspoon.org/docs/hs.html
[2] https://www.hammerspoon.org/docs/hs.settings.html
[3] https://www.hammerspoon.org/docs/hs.location.html
