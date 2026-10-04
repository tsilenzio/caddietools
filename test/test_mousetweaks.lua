-- Run: lua test/test_mousetweaks.lua   (from the repo root)
package.path = "./test/?.lua;" .. package.path
local stub = require("stub_hs")

local failures = 0
local function check(cond, label)
  if not cond then failures = failures + 1 print("FAIL " .. label) else print("ok   " .. label) end
end

-- The stub's doAfter fires immediately and its eventtap drops the callback, so
-- both are replaced with versions the test drives by hand
local function patch(env)
  env.timers = {}
  hs.timer.doAfter = function(delay, fn)
    local t = { delay = delay, fn = fn, running = true }
    function t:stop() self.running = false return self end
    function t:fire() self.running = false self.fn() end
    table.insert(env.timers, t)
    return t
  end
  hs.eventtap.new = function(types, fn)
    local tap = { types = types, fn = fn, running = false }
    function tap:start() self.running = true return self end
    function tap:stop() self.running = false return self end
    function tap:isEnabled() return self.running end
    env.tap = tap
    return tap
  end
end

-- `posted` collects events the Spoon posts, for the smoothing suite
local posted = {}

local function wrapEvent(p)
  local e = { p = p }
  function e:getProperty(k) return self.p[k] end
  function e:setProperty(k, v) self.p[k] = v return self end
  function e:copy()
    local q = {}
    for k, v in pairs(self.p) do q[k] = v end
    return wrapEvent(q)
  end
  function e:location(point) self.p.location = point return self end
  function e:post() table.insert(posted, self) end
  return e
end

local function fakeEvent(continuous, dy)
  return wrapEvent({
    scrollWheelEventIsContinuous = continuous,
    scrollWheelEventDeltaAxis1 = dy,
    scrollWheelEventPointDeltaAxis1 = dy * 10,
    scrollWheelEventFixedPtDeltaAxis1 = dy + 0.5,
    scrollWheelEventDeltaAxis2 = 3,
  })
end

-- A notch with no horizontal motion, the only kind that glides
local function verticalNotch(points)
  return wrapEvent({
    scrollWheelEventIsContinuous = 0,
    scrollWheelEventDeltaAxis1 = points < 0 and -1 or 1,
    scrollWheelEventPointDeltaAxis1 = points,
    scrollWheelEventFixedPtDeltaAxis1 = points / 10,
    scrollWheelEventDeltaAxis2 = 0,
    scrollWheelEventPointDeltaAxis2 = 0,
    eventTargetUnixProcessID = 4242,
  })
end

-- Core is reloaded too, since the Spoon's parts are cached in it and capture hs
-- functions when they load
local function load()
  stub.install(".")
  package.loaded["MouseTweaks"], package.loaded["CaddieCore"] = nil, nil
  local env = { summaries = {} }
  patch(env)
  stub.loadSpoon("CaddieCore")
  env.spoon = stub.loadSpoon("MouseTweaks")
  env.spoon:on("summary", function(s) table.insert(env.summaries, s) end, "Test")
  return env
end

local function runSuite()
  print("-- direction")
  local env = load()
  -- Smoothing has its own suite below
  env.spoon.smooth.enabled = false
  local sd = env.spoon

  sd:start()
  check(env.tap and env.tap.running, "start creates and starts the tap")
  check(env.tap.types[1] == "scrollWheel", "tap listens for scrollWheel")
  check(#env.timers == 0, "no timer while idle")

  local cont = fakeEvent(1, 4)
  check(env.tap.fn(cont) == false, "continuous event passes on")
  local p = cont.p
  check(p.scrollWheelEventDeltaAxis1 == 4 and p.scrollWheelEventPointDeltaAxis1 == 40
    and p.scrollWheelEventFixedPtDeltaAxis1 == 4.5, "continuous event untouched")

  local wheel = fakeEvent(0, 2)
  check(sd:process(wheel) == false, "wheel event passes on")
  p = wheel.p
  check(p.scrollWheelEventDeltaAxis1 == -2 and p.scrollWheelEventPointDeltaAxis1 == -20
    and p.scrollWheelEventFixedPtDeltaAxis1 == -2.5, "wheel event flipped on all three properties")
  check(p.scrollWheelEventDeltaAxis2 == 3, "horizontal axis untouched")

  for _ = 1, 5 do sd:process(fakeEvent(0, 1)) end
  for _ = 1, 3 do sd:process(fakeEvent(1, 1)) end
  check(#env.timers == 1, "timer armed once per burst")
  check(env.timers[1].delay == env.spoon.summaryDelay, "timer uses scrollSummaryDelay")
  check(#env.summaries == 0, "nothing published per event")

  local st = sd:stats()
  check(st.wheelEvents == 6 and st.continuousEvents == 4 and st.flipped == 6, "counters")

  env.timers[1]:fire()
  local s = env.summaries[1]
  check(#env.summaries == 1, "exactly one summary for the burst")
  check(s and s.wheelEvents == 6 and s.continuousEvents == 4 and s.flipped == 6
    and type(s.intervalS) == "number" and s.intervalS >= 0, "summary payload")

  -- Second burst rearms once and reports only its own events
  sd:process(fakeEvent(0, 1))
  sd:process(fakeEvent(1, 1))
  check(#env.timers == 2, "next burst arms a new timer")
  env.tap.running = false
  env.timers[2]:fire()
  s = env.summaries[2]
  check(#env.summaries == 2 and s.wheelEvents == 1 and s.continuousEvents == 1 and s.flipped == 1,
    "second summary counts only its burst")
  check(env.tap.running, "disabled tap restarted when the summary fires")

  -- The hot path allocates nothing once a burst is armed
  local ev = fakeEvent(0, 1)
  sd:process(ev)
  collectgarbage("collect")
  collectgarbage("stop")
  local before = collectgarbage("count")
  for _ = 1, 10000 do sd:process(ev) end
  local grew = collectgarbage("count") - before
  collectgarbage("restart")
  check(grew == 0, string.format("process allocates nothing (%.2f KB over 10000 calls)", grew))

  local tap, armed = env.tap, env.timers[#env.timers]
  sd:stop()
  check(not tap.running, "stop releases the tap")
  check(not armed.running, "stop cancels a pending summary timer")
  local timersBefore = #env.timers
  sd:process(fakeEvent(0, 1))
  check(#env.timers == timersBefore, "process after stop arms no timer")
  sd:start()
  check(env.tap ~= tap and env.tap.running, "restart creates a fresh tap")
  sd:stop()
  return env
end

local function bench(env, continuous)
  local sd = env.spoon
  sd:start()
  local ev = fakeEvent(continuous, 1)
  local n = 1e6
  sd:process(ev)
  local t0 = os.clock()
  for _ = 1, n do sd:process(ev) end
  local us = (os.clock() - t0) / n * 1e6
  sd:stop()
  print(string.format("bench %-10s %.4f us/call over %d calls",
    continuous == 0 and "wheel" or "continuous", us, n))
end

-- The clock, the repeating timer, and the screen under the cursor are all driven
-- by hand
local function runSmoothSuite()
  print("-- smoothing")
  local env = load()

  local clockNs = 0
  hs.timer.absoluteTime = function() return clockNs end
  local repeating = {}
  hs.timer.doEvery = function(interval, fn)
    local t = { interval = interval, fn = fn, running = true }
    function t:stop() self.running = false return self end
    table.insert(repeating, t)
    return t
  end
  local hz = 240
  local cursor = { x = 10, y = 20 }
  hs.mouse = {
    getCurrentScreen = function() return { currentMode = function() return { freq = hz } end } end,
    absolutePosition = function() return cursor end,
  }
  -- The Spoon captures absoluteTime when it loads, so it is reloaded after the patch
  package.loaded["MouseTweaks"], package.loaded["CaddieCore"] = nil, nil
  local sd = stub.loadSpoon("MouseTweaks")
  local cfg = sd.smooth
  cfg.enabled = true
  sd:start()

  local function clearPosted() for k in pairs(posted) do posted[k] = nil end end
  local function sumPosted()
    local total = 0
    for _, e in ipairs(posted) do total = total + e.p.scrollWheelEventPointDeltaAxis1 end
    return total
  end
  -- Advances the clock in ticks of `rate` Hz for `seconds`, or until the glide ends
  local function run(rate, seconds)
    local t = repeating[#repeating]
    for _ = 1, math.floor(seconds * rate + 0.5) do
      if not t.running then break end
      clockNs = clockNs + math.floor(1e9 / rate)
      t.fn()
    end
  end
  local notchDistance = math.max(20, cfg.minStep) * cfg.speed

  clearPosted()
  local notch = verticalNotch(-20)
  check(sd:process(notch) == true, "smooth " .. "vertical wheel notch is swallowed")
  check(notch.p.scrollWheelEventPointDeltaAxis1 == 20, "smooth " .. "swallowed notch was still flipped")
  check(#repeating == 1 and math.abs(repeating[1].interval - 1 / 240) < 1e-12, "smooth " .. "tick rate follows the screen, 240 Hz")
  check(#posted == 0, "smooth " .. "nothing posted before the first tick")

  run(240, 2)
  check(not repeating[1].running, "smooth " .. "timer stops once the glide settles")
  check(sd.glideTimer == nil and sd.template == nil, "smooth " .. "glide state released")
  check(math.abs(sumPosted() - notchDistance) < cfg.settle + 1,
    string.format("smooth " .. "glide covers the notch distance (%d of %.2f)", sumPosted(), notchDistance))
  local wellFormed = #posted > 0
  for _, e in ipairs(posted) do
    local p = e.p
    if not (p.scrollWheelEventIsContinuous == 1 and p.scrollWheelEventDeltaAxis1 == 0
      and math.type(p.scrollWheelEventPointDeltaAxis1) == "integer" and p.scrollWheelEventPointDeltaAxis1 > 0
      and p.scrollWheelEventFixedPtDeltaAxis1 == p.scrollWheelEventPointDeltaAxis1 / 10
      and p.eventSourceUserData == 0x4853534D4F4F5448) then wellFormed = false end
    if p.location ~= cursor then wellFormed = false end
  end
  check(wellFormed, "smooth " .. "posted events are marked, continuous, whole points, flipped, and at the cursor")

  -- The same notch scrolls the same distance in the same time at any tick rate
  local function scrolledAfter(rate, seconds)
    clearPosted()
    hz = rate
    sd:process(verticalNotch(-20))
    run(rate, seconds)
    local total = sumPosted()
    sd:_endGlide()
    return total
  end
  local at60, at240, at330 = scrolledAfter(60, 0.1), scrolledAfter(240, 0.1), scrolledAfter(330, 0.1)
  local model = notchDistance * (1 - math.exp(-0.1 / cfg.tau))
  check(math.abs(at60 - model) < 1 and math.abs(at240 - model) < 1 and math.abs(at330 - model) < 1,
    string.format("smooth " .. "rate independent at 0.1 s (60 Hz %d, 240 Hz %d, 330 Hz %d, model %.1f)", at60, at240, at330, model))
  check(math.abs(repeating[#repeating].interval - 1 / 330) < 1e-12, "smooth " .. "330 Hz screen ticks at 330 Hz")

  -- A stall longer than maxDt moves only as far as maxDt allows
  sd:process(verticalNotch(-20))
  local before = sd.pending
  clockNs = clockNs + 500 * 1000000
  repeating[#repeating].fn()
  check(math.abs((before - sd.pending) - before * (1 - math.exp(-cfg.maxDt / cfg.tau))) < 1e-9,
    "smooth " .. "dt capped at maxDt after a stall")
  sd:_endGlide()

  sd:process(verticalNotch(-20))
  sd:process(verticalNotch(-20))
  check(math.abs(sd.pending - 2 * notchDistance) < 1e-9, "smooth " .. "same-direction notches accumulate")
  sd:process(verticalNotch(20))
  check(math.abs(sd.pending + notchDistance) < 1e-9, "smooth " .. "opposite notch drops the rest and reverses")
  check(#repeating == 6, "smooth " .. "one timer per glide, not per notch")
  sd:_endGlide()

  -- Glide events are not checked against their target app, because macOS keeps
  -- reporting the app a glide started in
  sd:process(verticalNotch(-20))
  local glideEvent = function(pid)
    local e = verticalNotch(5)
    e.p.scrollWheelEventIsContinuous = 1
    e.p.eventSourceUserData = 0x4853534D4F4F5448
    e.p.eventTargetUnixProcessID = pid
    return e
  end
  check(sd:process(glideEvent(4242)) == false and sd.glideTimer ~= nil, "smooth " .. "glide event to the same app continues the glide")
  check(sd:process(glideEvent(0)) == false and sd.glideTimer ~= nil, "smooth " .. "glide event with unknown target continues the glide")
  local t = repeating[#repeating]
  check(sd:process(glideEvent(5555)) == false and sd.glideTimer ~= nil and t.running,
    "smooth: glide events pass untouched whatever app they report")
  sd:_endGlide()
  check(sd:process(glideEvent(5555)) == false, "smooth " .. "with no glide running, glide events pass on")

  -- A notch aimed at another app starts fresh instead of adding to the glide
  sd:process(verticalNotch(-20))
  local other = verticalNotch(-20)
  other.p.eventTargetUnixProcessID = 5555
  sd:process(other)
  check(math.abs(sd.pending - notchDistance) < 1e-9 and sd.glidePid == 5555, "smooth " .. "notch in another app starts a fresh glide")
  sd:_endGlide()

  local own = verticalNotch(-20)
  own.p.eventSourceUserData = 0x4853534D4F4F5448
  local wheelBefore = sd:stats().wheelEvents
  check(sd:process(own) == false and own.p.scrollWheelEventPointDeltaAxis1 == -20, "smooth " .. "own posted events pass untouched")
  check(sd:stats().wheelEvents == wheelBefore, "smooth " .. "own posted events are not counted")

  local diagonal = verticalNotch(-20)
  diagonal.p.scrollWheelEventPointDeltaAxis2 = 5
  check(sd:process(diagonal) == false and sd.glideTimer == nil, "smooth " .. "notch with horizontal motion passes on")

  hz = 0
  check(sd:_tickRate() == cfg.fallbackHz, "smooth " .. "0 Hz screen uses fallbackHz")
  hz = 1000
  check(sd:_tickRate() == cfg.maxHz, "smooth " .. "rate clamps to maxHz")

  sd:process(verticalNotch(-20))
  t = repeating[#repeating]
  sd:stop()
  check(not t.running and sd.glideTimer == nil, "smooth " .. "stop ends a running glide")
end

local env = runSuite()
bench(env, 0)
bench(env, 1)
runSmoothSuite()
print("(bench excludes the hs.eventtap.event bridge cost: fake getProperty/setProperty are Lua table lookups)")

print(failures == 0 and "ALL PASS" or (failures .. " FAILED"))
os.exit(failures == 0 and 0 or 1)
