-- Compile the production Fennel first, then run:
-- lua tests/auto-dark-mode-location-test.lua /path/to/auto-dark-mode-location.lua
-- All coordinates, clocks, OS APIs, and provider responses here are synthetic.
local compiled = assert(arg[1], "pass the compiled acquisition module path")
local tests = {}
local function test(name, fn) tests[#tests + 1] = {name, fn} end
local function eq(actual, expected, context)
  assert(actual == expected, (context or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local fixtures = {
  ['{"loc":"0,0"}'] = {loc = "0,0"},
  ['{"loc":"12.25,-45.5"}'] = {loc = "12.25,-45.5"},
  ['{"success":true,"latitude":8,"longitude":-9}'] = {success = true, latitude = 8, longitude = -9},
}
local function fixture(body, value) fixtures[body] = value; return body end
local function harness(options)
  options = options or {}
  local h = {time = 0, epoch = 1700000000, timers = {}, tasks = {}, trackers = {}, calls = {}, gets = 0, news = 0, logs = 0, decodes = 0}
  local function after(delay, fn)
    local t = {at = h.time + delay, fn = fn, active = true, id = #h.timers + 1}
    function t:stop() self.active = false; return self end
    h.timers[#h.timers + 1] = t
    return t
  end
  function h:advance(seconds)
    local target, limit = self.time + seconds, 0
    while true do
      local nextTimer
      for _, t in ipairs(self.timers) do
        if t.active and t.at <= target and (not nextTimer or t.at < nextTimer.at or (t.at == nextTimer.at and t.id < nextTimer.id)) then nextTimer = t end
      end
      if not nextTimer then break end
      limit = limit + 1; assert(limit < 1000, "timer loop")
      self.time = nextTimer.at; nextTimer.active = false; nextTimer.fn()
    end
    self.time = target
  end
  function h:pending()
    local n = 0
    for _, t in ipairs(self.timers) do if t.active then n = n + 1 end end
    return n
  end
  local location = {
    servicesEnabled = function() if options.servicesError then error("private services error") end; return options.enabled ~= false end,
    authorizationStatus = function() if options.authorizationError then error("private auth error") end; return options.authorization or "authorized" end,
    get = function() h.gets = h.gets + 1; if options.getError then error("private get error") end; return options.cached end,
    new = function()
      h.news = h.news + 1
      if options.newError then error("private tracker error") end
      if options.newNil then return nil end
      local t = {tracking = false, stopped = 0}
      function t:callback(...) eq(select("#", ...), 1, "native callback argument count"); self.fn = select(1, ...); return self end
      function t:startTracking()
        if options.trackError then error("private track error") end
        if options.trackFalse then return false end
        self.tracking = true
        return self
      end
      function t:stopTracking() self.tracking = false; self.stopped = self.stopped + 1; return self end
      function t:emit(message, value) if self.fn then self.fn(self, message, value) end end
      h.trackers[#h.trackers + 1] = t
      return t
    end,
    start = function() error("must not start shared location tracking") end,
    stop = function() error("must not stop shared location tracking") end,
  }
  if options.noLocation then location = nil end
  local hs = {
    location = location,
    timer = {doAfter = after, secondsSinceEpoch = function() return h.epoch + h.time end},
    json = {decode = function(body)
      h.decodes = h.decodes + 1
      local value = fixtures[body]
      if value == nil then
        if options.decodeNil then return nil end
        error("private JSON parse error: " .. body)
      end
      return value
    end},
    task = {new = function(path, callback, args)
      local source = args[#args]:find("ipinfo", 1, true) and "ipinfo" or "ipwhois"
      local response = (options.http or {})[source] or {exit = 7, status = 0}
      if response.createError then error("private task creation error") end
      if response.createNil then return nil end
      local t = {source = source, path = path, args = args, callback = callback, running = false, terminated = 0}
      function t:finish(exit, body, status, stderr)
        self.running = false
        self.callback(exit, (body or "") .. "\n" .. string.format("%03d", status or 0), stderr or "private stderr")
      end
      function t:setCallback(fn) self.callback = fn; self.callbackCleared = fn == nil; return self end
      function t:start()
        if response.startError then error("private task start error") end
        if response.startFalse then return false end
        self.running = true
        if not response.hang then
          self.event = after(response.delay or 0, function() self:finish(response.exit or 0, response.body, response.status or 200) end)
        end
        return self
      end
      function t:terminate()
        self.running = false; self.terminated = self.terminated + 1
        if self.event then self.event:stop() end
        if options.callbackOnTerminate then self:finish(15, "private terminated body", 0) end
        return self
      end
      h.tasks[#h.tasks + 1] = t
      return t
    end},
  }
  if options.noTask then hs.task = nil end
  if options.noJSON then hs.json = nil end
  local clockReads = 0
  local env = setmetatable({hs = hs, os = {time = function()
    clockReads = clockReads + 1
    return math.floor(h.epoch + h.time) + (options.tickOnClockRead and clockReads - 1 or 0)
  end}, print = function() h.logs = h.logs + 1 end}, {__index = _G})
  local chunk = loadfile(compiled, "t", env)
  h.module = chunk and chunk() or {}
  assert(type(h.module.acquire) == "function", "compiled acquisition module must expose acquire(callback)")
  function h:acquire()
    return self.module.acquire(function(loc, err) self.calls[#self.calls + 1] = {location = loc, err = err} end)
  end
  return h
end
local function fix(timestamp, latitude, longitude)
  return {latitude = latitude or 0, longitude = longitude or 0, horizontalAccuracy = 20, timestamp = timestamp or 1699999999.5}
end

test("authorized cached fix completes once, deferred, with source and observation time", function()
  local h = harness{cached = fix()}
  local cancel = h:acquire()
  eq(type(cancel), "function"); eq(#h.calls, 0, "synchronous callback count")
  h:advance(0)
  eq(#h.calls, 1); eq(h.calls[1].err, nil)
  local loc = h.calls[1].location
  eq(loc.latitude, 0); eq(loc.longitude, 0); eq(loc.source, "corelocation")
  eq(loc.acquiredAt, h.epoch); eq(loc.observedAt, 1699999999.5)
  eq(h.gets, 1); eq(h.news, 0); eq(#h.tasks, 0); eq(h:pending(), 0)
  cancel(); cancel(); h:advance(30); eq(#h.calls, 1)
end)

test("denied permission skips Core Location without prompting and uses IPinfo", function()
  local h = harness{authorization = "denied", cached = fix(), http = {ipinfo = {body = '{"loc":"12.25,-45.5"}'}}}
  h:acquire(); eq(#h.calls, 0); h:advance(0)
  eq(#h.calls, 1); eq(h.calls[1].err, nil)
  local loc = h.calls[1].location
  eq(loc.source, "ipinfo"); eq(loc.latitude, 12.25); eq(loc.longitude, -45.5)
  eq(loc.observedAt, loc.acquiredAt); eq(h.gets, 0); eq(h.news, 0); eq(#h.tasks, 1); eq(h:pending(), 0)
end)

test("HTTP error falls back from IPinfo to IPWhois", function()
  local h = harness{enabled = false, http = {ipinfo = {status = 429, body = "private rate-limit body"}, ipwhois = {body = '{"success":true,"latitude":8,"longitude":-9}'}}}
  h:acquire(); h:advance(0)
  eq(#h.calls, 1); eq(h.calls[1].err, nil); eq(h.calls[1].location.source, "ipwhois")
  eq(#h.tasks, 2); eq(h.gets, 0); eq(h.news, 0); eq(h:pending(), 0)
end)

test("all unavailable sources complete once with sanitized structured failure", function()
  local h = harness{authorization = "denied", http = {ipinfo = {exit = 7}, ipwhois = {status = 503, body = "secret=private"}}}
  h:acquire(); h:advance(0); eq(#h.calls, 1); eq(h.calls[1].location, nil)
  local err = h.calls[1].err
  eq(err.code, "all-sources-failed"); eq(#err.failures, 3)
  eq(err.failures[1].source, "corelocation"); eq(err.failures[2].source, "ipinfo"); eq(err.failures[3].source, "ipwhois")
  eq(err.failures[3].httpStatus, 503)
  for key in pairs(err) do assert(key == "code" or key == "failures", "unexpected error data") end
  for _, failure in ipairs(err.failures) do
    for key in pairs(failure) do assert(key == "source" or key == "code" or key == "httpStatus", "unsafe failure field") end
    assert(not failure.code:find("private", 1, true), "leaked private error")
  end
  h:advance(100); eq(#h.calls, 1); eq(h:pending(), 0)
end)

test("transport is curl argument array with bounded secure defaults", function()
  local h = harness{authorization = "denied", http = {ipinfo = {body = '{"loc":"0,0"}'}}}
  h:acquire(); h:advance(0)
  local t = h.tasks[1]; eq(t.path, "/usr/bin/curl"); eq(t.args[1], "-q")
  local values, flags = {}, {}
  for i, value in ipairs(t.args) do values[value] = t.args[i + 1]; flags[value] = true end
  eq(values["--connect-timeout"], "3"); eq(values["--max-time"], "8")
  eq(values["--max-filesize"], "16384"); eq(values["--proto"], "=https"); eq(values["--max-redirs"], "0")
  eq(values["--header"], "Accept: application/json"); eq(values["--write-out"], "\n%{http_code}")
  eq(t.args[#t.args], "https://ipinfo.io/json")
  assert(not flags["--location"] and not flags["-L"] and not flags["--insecure"] and not flags["-k"])
  eq(h.calls[1].location.latitude, 0); eq(h.calls[1].location.longitude, 0)
end)

test("authorized fresh tracking accepts the newest valid fix and releases owned tracker", function()
  local h = harness{}
  h:acquire(); h:advance(0); eq(#h.calls, 0); eq(#h.trackers, 1); eq(#h.tasks, 0)
  local t = h.trackers[1]; assert(t.tracking)
  t:emit("didUpdateLocations", {fix(1699999998, 1, 2), fix(1699999999, 3, 4)})
  eq(#h.calls, 1); eq(h.calls[1].location.latitude, 3); eq(h.calls[1].location.observedAt, 1699999999)
  eq(h.calls[1].location.source, "corelocation"); eq(t.tracking, false); eq(t.stopped, 1); eq(t.fn, nil)
  eq(h:pending(), 0); h:advance(30); eq(#h.calls, 1)
end)

test("authorized tracking is limited to two seconds before network fallback", function()
  local h = harness{http = {ipinfo = {body = '{"loc":"0,0"}'}}}
  h:acquire(); h:advance(1.99); eq(#h.calls, 0); eq(#h.tasks, 0)
  h:advance(0.01); eq(#h.calls, 1); eq(h.calls[1].location.source, "ipinfo")
  eq(h.trackers[1].tracking, false); eq(h.trackers[1].stopped, 1); eq(h:pending(), 0)
end)

for _, status in ipairs({"undefined", "denied", "restricted", "notDetermined", "unknown"}) do
  test("authorization " .. status .. " never gets or starts native location", function()
    local h = harness{authorization = status, cached = fix(), http = {ipinfo = {body = '{"loc":"0,0"}'}}}
    h:acquire(); h:advance(0)
    eq(h.gets, 0); eq(h.news, 0); eq(h.calls[1].location.source, "ipinfo")
  end)
end
for _, option in ipairs({"noLocation", "servicesError", "authorizationError", "newError", "newNil", "getError", "trackError", "trackFalse"}) do
  test("native API " .. option .. " failure permits fallback", function()
    local opts = {http = {ipinfo = {body = '{"loc":"0,0"}'}}}; opts[option] = true
    local h = harness(opts); h:acquire(); h:advance(2)
    eq(#h.calls, 1); eq(h.calls[1].location.source, "ipinfo"); eq(h:pending(), 0)
  end)
end

local invalidFixes = {
  {"stale timestamp", function(f) f.timestamp = 1699913599 end},
  {"missing timestamp", function(f) f.timestamp = nil end},
  {"future timestamp", function(f) f.timestamp = 1700003600 end},
  {"negative accuracy", function(f) f.horizontalAccuracy = -1 end},
  {"missing accuracy", function(f) f.horizontalAccuracy = nil end},
  {"NaN accuracy", function(f) f.horizontalAccuracy = 0/0 end},
  {"latitude range", function(f) f.latitude = 91 end},
  {"longitude range", function(f) f.longitude = -181 end},
  {"infinite coordinate", function(f) f.longitude = math.huge end},
  {"NaN coordinate", function(f) f.latitude = 0/0 end},
  {"string coordinate", function(f) f.latitude = "10" end},
}
for _, entry in ipairs(invalidFixes) do
  test("reject native " .. entry[1] .. " before fallback", function()
    local f = fix(); entry[2](f)
    local h = harness{cached = f, http = {ipinfo = {body = '{"loc":"0,0"}'}}}
    h:acquire(); h:advance(2); eq(#h.calls, 1); eq(h.calls[1].location.source, "ipinfo"); eq(h.gets, 1)
  end)
end

for _, message in ipairs({"didFailWithError", "didChangeAuthorizationStatus"}) do
  test("native " .. message .. " ends tracking and falls back immediately", function()
    local h = harness{http = {ipinfo = {body = '{"loc":"0,0"}'}}}
    h:acquire(); h:advance(0)
    h.trackers[1]:emit(message, message == "didFailWithError" and "private GPS failure" or "denied")
    h:advance(0); eq(h.calls[1].location.source, "ipinfo"); eq(h.trackers[1].tracking, false); eq(h:pending(), 0)
  end)
end

test("malformed native updates do not throw or extend native deadline", function()
  local h = harness{http = {ipinfo = {body = '{"loc":"0,0"}'}}}
  h:acquire(); h:advance(0)
  h.trackers[1]:emit("didUpdateLocations", "private malformed message")
  h.trackers[1]:emit("didUpdateLocations", {false, {}, fix(1699913599)})
  eq(#h.calls, 0); h:advance(2); eq(h.calls[1].location.source, "ipinfo")
end)

local badIPinfo = {
  {"malformed JSON", "{not-json"},
  {"null", fixture("null", false)},
  {"array", fixture("[]", {})},
  {"missing loc", fixture('{"city":"synthetic"}', {city = "synthetic"})},
  {"latitude out of range", fixture('{"loc":"91,0"}', {loc = "91,0"})},
  {"longitude out of range", fixture('{"loc":"0,-181"}', {loc = "0,-181"})},
  {"infinity", fixture('{"loc":"1e999,0"}', {loc = "1e999,0"})},
  {"trailing data", fixture('{"loc":"1,2,3"}', {loc = "1,2,3"})},
  {"hexadecimal", fixture('{"loc":"0x10,0"}', {loc = "0x10,0"})},
  {"oversized response", string.rep(" ", 16385) .. '{"loc":"0,0"}'},
}
for _, entry in ipairs(badIPinfo) do
  test("IPinfo " .. entry[1] .. " falls back safely", function()
    if entry[1] == "oversized response" then fixture(entry[2], {loc = "0,0"}) end
    local h = harness{authorization = "denied", http = {ipinfo = {body = entry[2]}, ipwhois = {body = '{"success":true,"latitude":8,"longitude":-9}'}}}
    h:acquire(); h:advance(0); eq(#h.calls, 1); eq(h.calls[1].location.source, "ipwhois"); eq(h:pending(), 0)
  end)
end
local badIPwhois = {
  {"false success", {success = false, latitude = 8, longitude = -9}},
  {"missing success", {latitude = 8, longitude = -9}},
  {"string success", {success = "true", latitude = 8, longitude = -9}},
  {"string latitude", {success = true, latitude = "8", longitude = -9}},
  {"boolean longitude", {success = true, latitude = 8, longitude = false}},
  {"NaN latitude", {success = true, latitude = 0/0, longitude = -9}},
  {"infinite longitude", {success = true, latitude = 8, longitude = math.huge}},
  {"out of range latitude", {success = true, latitude = -91, longitude = -9}},
}
for i, entry in ipairs(badIPwhois) do
  test("IPWhois " .. entry[1] .. " is a clean acquisition failure", function()
    local body = fixture('{"syntheticCase":' .. i .. '}', entry[2])
    local h = harness{authorization = "denied", http = {ipinfo = {exit = 7}, ipwhois = {body = body}}}
    h:acquire(); h:advance(0); eq(#h.calls, 1); eq(h.calls[1].location, nil)
    eq(h.calls[1].err.code, "all-sources-failed"); eq(h:pending(), 0)
  end)
end

test("HTTP redirects are not accepted as a location result", function()
  local h = harness{authorization = "denied", http = {ipinfo = {status = 302, body = '{"loc":"0,0"}'}, ipwhois = {exit = 7}}}
  h:acquire(); h:advance(0); eq(h.calls[1].location, nil); eq(h.calls[1].err.failures[2].httpStatus, 302)
end)

for _, option in ipairs({"createError", "createNil", "startError", "startFalse"}) do
  test("task " .. option .. " advances to alternate provider", function()
    local bad = {}; bad[option] = true
    local h = harness{authorization = "denied", http = {ipinfo = bad, ipwhois = {body = '{"success":true,"latitude":8,"longitude":-9}'}}}
    h:acquire(); h:advance(0); eq(#h.calls, 1); eq(h.calls[1].location.source, "ipwhois"); eq(h:pending(), 0)
  end)
end

test("hung IPinfo is terminated at eight seconds and alternate provider succeeds", function()
  local h = harness{authorization = "denied", callbackOnTerminate = true, http = {ipinfo = {hang = true}, ipwhois = {body = '{"success":true,"latitude":8,"longitude":-9}'}}}
  h:acquire(); h:advance(7.99); eq(#h.calls, 0); eq(#h.tasks, 1)
  h:advance(0.01); eq(#h.calls, 1); eq(h.calls[1].location.source, "ipwhois")
  eq(h.tasks[1].terminated, 1); eq(h.tasks[2].terminated, 0); eq(h:pending(), 0)
end)

test("late timed-out provider callback cannot overwrite active alternate provider", function()
  local h = harness{authorization = "denied", http = {ipinfo = {hang = true}, ipwhois = {body = '{"success":true,"latitude":8,"longitude":-9}', delay = 1}}}
  h:acquire(); h:advance(8); eq(#h.tasks, 2); eq(#h.calls, 0)
  h.tasks[1]:finish(0, '{"loc":"0,0"}', 200)
  h.tasks[1]:finish(7, "private late failure", 0)
  eq(#h.calls, 0); eq(#h.tasks, 2)
  h:advance(1); eq(#h.calls, 1); eq(h.calls[1].location.source, "ipwhois"); eq(h:pending(), 0)
end)

test("all hung sources finish with clean failure within eighteen seconds", function()
  local h = harness{http = {ipinfo = {hang = true}, ipwhois = {hang = true}}}
  h:acquire(); h:advance(17.99); eq(#h.calls, 0)
  h:advance(0.01); eq(#h.calls, 1); eq(h.calls[1].location, nil); eq(h.calls[1].err.code, "all-sources-failed")
  eq(#h.calls[1].err.failures, 3); eq(h.trackers[1].stopped, 1)
  eq(h.tasks[1].terminated, 1); eq(h.tasks[2].terminated, 1); eq(h:pending(), 0)
  h:advance(100); eq(#h.calls, 1)
end)

test("whole-attempt watchdog completes and cleans up even if source timeout is lost", function()
  local h = harness{authorization = "denied", http = {ipinfo = {hang = true}}}
  h:acquire(); h:advance(0)
  for _, t in ipairs(h.timers) do if t.at == 8 then t:stop() end end
  h:advance(20); eq(#h.calls, 1); eq(h.calls[1].location, nil); eq(h.calls[1].err.code, "deadline-exceeded")
  eq(h.tasks[1].terminated, 1); eq(h:pending(), 0)
  h.tasks[1]:finish(0, '{"loc":"0,0"}', 200); eq(#h.calls, 1)
end)

test("cancel before kickoff is idempotent and starts no sources", function()
  local h = harness{cached = fix()}; local cancel = h:acquire(); cancel(); cancel()
  h:advance(50); eq(#h.calls, 0); eq(h.gets, 0); eq(h.news, 0); eq(#h.tasks, 0); eq(h:pending(), 0)
end)

test("cancel native tracking detaches its callback and ignores already-queued fixes", function()
  local h = harness{}; local cancel = h:acquire(); h:advance(0)
  local t = h.trackers[1]; local queued = t.fn
  cancel(); cancel(); queued(t, "didUpdateLocations", {fix()})
  h:advance(50); eq(#h.calls, 0); eq(t.stopped, 1); eq(t.fn, nil); eq(#h.tasks, 0); eq(h:pending(), 0)
end)

test("cancel HTTP releases task and suppresses reentrant termination callback", function()
  local h = harness{authorization = "denied", callbackOnTerminate = true, http = {ipinfo = {hang = true}}}
  local cancel = h:acquire(); h:advance(0); cancel(); cancel()
  h.tasks[1]:finish(0, '{"loc":"0,0"}', 200)
  h:advance(50); eq(#h.calls, 0); eq(h.tasks[1].terminated, 1); eq(#h.tasks, 1); eq(h:pending(), 0)
end)

test("canceled old attempt cannot alter a newer attempt", function()
  local h = harness{authorization = "denied", http = {ipinfo = {hang = true}}}
  local cancel = h:acquire(); h:advance(0); local old = h.tasks[1]
  cancel(); h:acquire(); h:advance(0); local current = h.tasks[2]
  old:finish(0, '{"loc":"12.25,-45.5"}', 200); eq(#h.calls, 0)
  current:finish(0, '{"loc":"0,0"}', 200)
  eq(#h.calls, 1); eq(h.calls[1].location.latitude, 0); eq(h:pending(), 0)
end)

test("late native callback after fallback cannot replace network result", function()
  local h = harness{http = {ipinfo = {hang = true}}}
  h:acquire(); h:advance(0); local t = h.trackers[1]; local queued = t.fn
  h:advance(2); queued(t, "didUpdateLocations", {fix()}); eq(#h.calls, 0)
  h.tasks[1]:finish(0, '{"loc":"12.25,-45.5"}', 200)
  eq(h.calls[1].location.source, "ipinfo"); eq(#h.calls, 1); eq(h:pending(), 0)
end)

test("never-launched task detaches callback without trying to terminate it", function()
  local h = harness{authorization = "denied", http = {ipinfo = {startFalse = true}, ipwhois = {exit = 7}}}
  h:acquire(); h:advance(0); eq(#h.calls, 1)
  eq(h.tasks[1].callbackCleared, true); eq(h.tasks[1].terminated, 0)
  eq(h.calls[1].err.failures[2].code, "task-start-failed"); eq(h:pending(), 0)
end)

test("curl maximum-size exit has a precise sanitized error code", function()
  local h = harness{authorization = "denied", http = {ipinfo = {exit = 63}, ipwhois = {exit = 7}}}
  h:acquire(); h:advance(0); eq(h.calls[1].err.failures[2].code, "response-too-large")
end)

for _, body in ipairs({"", "<html>private outage</html>", "{partial"}) do
  test("obviously non-JSON response avoids native decoder diagnostics: " .. (body == "" and "empty" or body:sub(1, 1)), function()
    local h = harness{authorization = "denied", decodeNil = true, http = {ipinfo = {body = body}, ipwhois = {exit = 7}}}
    h:acquire(); h:advance(0); eq(h.calls[1].err.code, "all-sources-failed"); eq(h.decodes, 0); eq(h.logs, 0)
  end)
end

test("native decoder returning nil is handled like a thrown parse error", function()
  local h = harness{authorization = "denied", decodeNil = true, http = {ipinfo = {body = '{"broken":}'}, ipwhois = {body = '{"success":true,"latitude":8,"longitude":-9}'}}}
  h:acquire(); h:advance(0); eq(h.calls[1].location.source, "ipwhois"); eq(h.logs, 0)
end)

for _, option in ipairs({"noTask", "noJSON"}) do
  test("missing " .. option .. " module produces a clean failure", function()
    local opts = {authorization = "denied", http = {ipinfo = {body = '{"loc":"0,0"}'}, ipwhois = {exit = 7}}}; opts[option] = true
    local h = harness(opts); h:acquire(); h:advance(0)
    eq(#h.calls, 1); eq(h.calls[1].err.code, "all-sources-failed"); eq(h:pending(), 0)
  end)
end

for _, bytes in ipairs({16384, 16385}) do
  test("body size boundary " .. bytes .. " bytes", function()
    local base = '{"loc":"0,0"}'
    local body = fixture(string.rep(" ", bytes - #base) .. base, {loc = "0,0"})
    local h = harness{authorization = "denied", http = {ipinfo = {body = body}, ipwhois = {exit = 7}}}
    h:acquire(); h:advance(0)
    eq(#h.calls, 1)
    if bytes == 16384 then eq(h.calls[1].location.source, "ipinfo") else eq(h.calls[1].err.failures[2].code, "response-too-large") end
  end)
end

test("nil stdout from invalid UTF-8 cannot escape the task callback", function()
  local h = harness{authorization = "denied", http = {ipinfo = {hang = true}, ipwhois = {exit = 7}}}
  h:acquire(); h:advance(0); h.tasks[1].callback(0, nil, "private stderr"); h:advance(0)
  eq(#h.calls, 1); eq(h.calls[1].err.failures[2].code, "invalid-response"); eq(h:pending(), 0)
end)

test("native authorized notification continues tracking", function()
  local h = harness{}; h:acquire(); h:advance(0)
  h.trackers[1]:emit("didChangeAuthorizationStatus", "authorized"); eq(#h.tasks, 0); eq(#h.calls, 0)
  h.trackers[1]:emit("didUpdateLocations", {fix(), {latitude = 500}})
  eq(#h.calls, 1); eq(h.calls[1].location.source, "corelocation"); eq(h:pending(), 0)
end)

test("native fractional fix timestamp is preserved without inventing precision for acquisition", function()
  local h = harness{cached = fix(1700000000.7)}; h:acquire(); h:advance(0)
  eq(h.calls[1].location.observedAt, 1700000000.7); eq(h.calls[1].location.acquiredAt, 1700000000)
end)

test("watchdog also releases native tracker", function()
  local h = harness{}; h:acquire(); h:advance(0)
  for _, t in ipairs(h.timers) do if t.at == 2 then t:stop() end end
  h:advance(20); eq(h.calls[1].err.code, "deadline-exceeded"); eq(h.trackers[1].stopped, 1)
  eq(h.trackers[1].fn, nil); eq(h:pending(), 0)
end)

test("throwing caller still leaves acquisition completed with resources released", function()
  local h = harness{cached = fix()}; local calls = 0
  local cancel = h.module.acquire(function() calls = calls + 1; error("synthetic caller exception") end)
  local ok = pcall(function() h:advance(0) end)
  eq(ok, false); eq(calls, 1); eq(h:pending(), 0); cancel(); h:advance(50); eq(calls, 1)
end)

test("cancel called inside completion is safe", function()
  local h = harness{cached = fix()}; local calls, cancel = 0
  cancel = h.module.acquire(function() calls = calls + 1; cancel(); cancel() end)
  h:advance(50); eq(calls, 1); eq(h:pending(), 0)
end)

test("two independent acquisitions do not share task or generation state", function()
  local h = harness{authorization = "denied", http = {ipinfo = {hang = true}}}
  h:acquire(); h:acquire(); h:advance(0); eq(#h.tasks, 2)
  h.tasks[2]:finish(0, '{"loc":"0,0"}', 200)
  h.tasks[1]:finish(0, '{"loc":"12.25,-45.5"}', 200)
  eq(#h.calls, 2); eq(h.calls[1].location.latitude, 0); eq(h.calls[2].location.latitude, 12.25); eq(h:pending(), 0)
end)

test("coordinate boundary values are valid for native and network fixes", function()
  local native = harness{cached = fix(nil, 90, -180)}
  native:acquire(); native:advance(0); eq(native.calls[1].location.source, "corelocation")
  local body = fixture('{"loc":"-90,180"}', {loc = "-90,180"})
  local network = harness{authorization = "denied", http = {ipinfo = {body = body}}}
  network:acquire(); network:advance(0)
  eq(network.calls[1].location.latitude, -90); eq(network.calls[1].location.longitude, 180)
end)

test("repeated failed acquisitions do not retain application timers or log data", function()
  local h = harness{authorization = "denied"}
  for _ = 1, 100 do h:acquire(); h:advance(0); eq(h:pending(), 0) end
  eq(#h.calls, 100); eq(#h.tasks, 200); eq(h.logs, 0)
end)

test("network observation and acquisition share one retrieval timestamp across a second boundary", function()
  local h = harness{authorization = "denied", tickOnClockRead = true, http = {ipinfo = {body = '{"loc":"0,0"}'}}}
  h:acquire(); h:advance(0)
  eq(h.calls[1].location.observedAt, h.calls[1].location.acquiredAt)
end)

local failed = 0
for _, entry in ipairs(tests) do
  local ok, err = pcall(entry[2])
  if ok then io.write("PASS ", entry[1], "\n") else failed = failed + 1; io.write("FAIL ", entry[1], ": ", tostring(err), "\n") end
end
io.write(string.format("%d checks: %d passed, %d failed\n", #tests, #tests - failed, failed))
os.exit(failed == 0 and 0 or 1)
