-- Run: lua test/test_sidecarusb.lua   (from the repo root)
-- SidecarUSB with the USB watcher, timers, and sidecarctl tasks driven by hand.
package.path = "./test/?.lua;" .. package.path
local stub = require("stub_hs")

local failures = 0
local function check(cond, label)
  if not cond then failures = failures + 1 print("FAIL " .. label) else print("ok   " .. label) end
end

local IPAD = { vendorID = 0x05AC, productName = "iPad", productID = 1 }
local KEYBOARD = { vendorID = 0x05AC, productName = "Magic Keyboard", productID = 2 }

local env

local function boot(settings)
  for name in pairs(package.loaded) do
    if name:match("^%u%a+$") then package.loaded[name] = nil end
  end
  stub.install(".")
  env = { timers = {}, tasks = {}, attached = {}, exists = true, screens = {}, dialogs = {} }
  hs.application.applicationsForBundleID = function(id)
    return id == "com.apple.UserNotificationCenter" and { { pid = function() return 99 end } } or {}
  end
  hs.axuielement = {
    applicationElement = function()
      return { attributeValue = function(_, key) if key == "AXWindows" then return env.dialogs end end }
    end,
    observer = { new = function()
      local o = {}
      function o:callback(fn) env.windowCreated = fn return self end
      function o:addWatcher() return self end
      function o:start() self.running = true env.observer = self return self end
      function o:stop() self.running = false return self end
      return o
    end },
  }
  hs.screen.allScreens = function()
    local list = {}
    for _, name in ipairs(env.screens) do list[#list + 1] = { name = function() return name end } end
    return list
  end
  hs.screen.watcher = { new = function(fn)
    env.screensChanged = fn
    local w = {}
    function w:start() return self end
    function w:stop() return self end
    return w
  end }
  hs.fs = {
    attributes = function() return env.exists and "file" or nil end,
    pathToAbsolute = function(p) return "/repo/Spoons/SidecarUSB.spoon" end,
  }
  hs.timer.doAfter = function(delay, fn)
    local t = { delay = delay, fn = fn, running = true }
    function t:stop() self.running = false end
    table.insert(env.timers, t)
    return t
  end
  hs.task = { new = function(path, cb, args)
    local t = { path = path, cb = cb, args = args, running = false }
    function t:start() self.running = true return self end
    function t:isRunning() return self.running end
    function t:terminate() self.running = false self.terminated = true end
    function t:finish(code, out) self.running = false self.cb(code, out or "", "") end
    table.insert(env.tasks, t)
    return t
  end }
  hs.usb = {
    watcher = { new = function(fn)
      env.usb = fn
      local w = {}
      function w:start() self.running = true return self end
      function w:stop() self.running = false return self end
      env.watcher = w
      return w
    end },
    attachedDevices = function() return env.attached end,
  }
  local s = stub.loadSpoon("SidecarUSB")
  for k, v in pairs(settings or {}) do s[k] = v end
  return s
end

local function fire()
  local t = table.remove(env.timers, 1)
  if t and t.running then t.fn() end
  return t
end
local function lastTask() return env.tasks[#env.tasks] end
local function argsOf(t) return table.concat(t.args, " ") end
local function event(device, kind)
  local e = { eventType = kind }
  for k, v in pairs(device) do e[k] = v end
  return e
end
local function lastAlert() return hs._log[#hs._log] end

-- Without sidecarctl installed nothing runs
local s = boot()
env.exists = false
s:start()
env.usb(event(IPAD, "added"))
check(#env.timers == 0 and #env.tasks == 0, "without sidecarctl a plug runs nothing")
check(lastAlert():find("sidecarctl not installed", 1, true), "and says so")
s:stop()

-- Plug in: wait, then connect over the cable, sidecarctl picking the one iPad
s = boot()
s:start()
env.usb(event(KEYBOARD, "added"))
check(#env.timers == 0, "other USB devices are ignored")
env.usb(event(IPAD, "added"))
check(#env.timers == 1 and env.timers[1].delay == 2, "a plug waits connectDelay before trying")
fire()
check(lastTask().path == "/opt/homebrew/bin/sidecarctl", "sidecarctl is run from Homebrew's bin")
check(argsOf(lastTask()) == "connect --connection wired", "with no device it connects without naming one, got " .. argsOf(lastTask()))
lastTask():finish(0, "connected to Test iPad\n")
check(s.connected and lastAlert() == "alert: Sidecar: connected to Test iPad", "a success is remembered and shown")

-- Unplug: disconnect
env.usb(event(IPAD, "removed"))
check(argsOf(lastTask()) == "disconnect" and not s.connected, "an unplug disconnects")
lastTask():finish(0, "disconnected from Test iPad\n")
check(lastAlert() == "alert: Sidecar: disconnected from Test iPad", "and says so")
s:stop()

-- Two iPads and no device: sidecarctl refuses, and retrying would not help
s = boot()
s:start()
env.usb(event(IPAD, "added"))
fire()
lastTask():finish(6, "more than one Sidecar device reachable, name one: A, B\n")
check(#env.timers == 0 and lastAlert() == "alert: Sidecar: more than one iPad reachable, set device",
  "exit code 6 is not retried and says what to set")
s:stop()

-- A locked iPad fails with code 4, and connecting is retried until attempts run out
s = boot({ device = "Desk iPad", attempts = 3, retryDelay = 3, transport = false })
s:start()
env.usb(event(IPAD, "added"))
fire()
check(argsOf(lastTask()) == "connect Desk iPad --connection system", "a device is passed, and no transport leaves the choice to Sidecar")
lastTask():finish(4)
check(#env.timers == 1 and env.timers[1].delay == 3, "a failure retries after retryDelay")
fire()
lastTask():finish(4)
fire()
lastTask():finish(4)
check(#env.timers == 0 and lastAlert() == "alert: Sidecar: could not connect (exit code 4)", "after the last attempt it gives up and says why")
check(#env.tasks == 3, "three attempts in all")
s:stop()

-- An iPad that is not ready, or not yet seen on USB, is tried again
s = boot({ refreshRate = false })
s:start()
env.usb(event(IPAD, "added"))
fire()
lastTask():finish(9, "Test iPad reports it is not ready.\n")
check(#env.timers == 1 and env.timers[1].delay == 3, "exit code 9, not ready, is retried")
fire()
lastTask():finish(8, "no iPad attached by USB\n")
check(#env.timers == 1, "exit code 8, no cable seen yet, is retried")
fire()
lastTask():finish(0, "connected to Test iPad\n")
check(s.connected, "and the next try connects")

-- An unplug with no session left to end says nothing
local before = #hs._log
env.usb(event(IPAD, "removed"))
lastTask():finish(0, "not connected to Test iPad\n")
check(#hs._log == before, "sidecarctl's \"not connected\" is not shown")
s:stop()

-- Unplugged mid-connect: the running connect is stopped, its late callback ignored
s = boot({ device = "Desk iPad" })
s:start()
env.usb(event(IPAD, "added"))
fire()
local connecting = lastTask()
env.usb(event(IPAD, "removed"))
check(connecting.terminated, "an unplug stops a connect in flight")
check(argsOf(lastTask()) == "disconnect Desk iPad", "and disconnects anyway, in case it got through")
connecting:finish(15)
check(#env.timers == 0, "the stopped connect's callback schedules no retry")
s:stop()

-- Plugged in already at start
s = boot({ device = "Desk iPad" })
env.attached = { KEYBOARD, IPAD }
s:start()
check(#env.timers == 1, "an iPad already plugged in at start gets connected")
s:stop()
check(not env.watcher.running and not env.timers[1].running, "stop releases the watcher and the pending connect")

-- A Sidecar alert window, listed already or, with later, created after the failure
local function dialog(title, later)
  local ok = { pressed = false }
  function ok:attributeValue(key) return ({ AXRole = "AXButton", AXTitle = "OK" })[key] end
  function ok:performAction(action) if action == "AXPress" then self.pressed = true end end
  local text = { attributeValue = function(_, key) return ({ AXRole = "AXStaticText", AXValue = title })[key] end }
  local win = { attributeValue = function(_, key) if key == "AXChildren" then return { text, ok } end end }
  if not later then env.dialogs[#env.dialogs + 1] = win end
  return ok, win
end

-- A failed connect dismisses Sidecar's dialog for that device at once, and no other
s = boot()
s:start()
env.usb(event(IPAD, "added"))
fire()
local ours = dialog("Unable to Connect to “Test iPad”")
local other = dialog("Unable to Connect to “Other iPad”")
lastTask():finish(4, "connect to Test iPad failed: SidecarErrorServiceDisconnected\n")
check(ours.pressed, "a failed connect's dialog is dismissed right away")
check(not other.pressed, "a dialog about another device is left alone")

-- One that appears just after the failure is caught as its window is created, until
-- the watch ends
local late, lateWin = dialog("Unable to Connect to “Test iPad”", true)
env.windowCreated(env.observer, lateWin)
check(late.pressed and env.observer.running, "a dialog created just after the failure is dismissed")
for _, t in ipairs(env.timers) do
  if t.delay == 5 then t.fn() end
end
check(not env.observer.running, "the watch ends after a few seconds")
s:stop()

-- A connect that succeeds dismisses nothing
s = boot()
s:start()
env.usb(event(IPAD, "added"))
fire()
ours = dialog("Unable to Connect to “Test iPad”")
lastTask():finish(0, "connected to Test iPad\n")
check(not ours.pressed and env.observer == nil, "a connect that never failed dismisses nothing")
s:stop()

local SIDECAR = "Sidecar Display (AirPlay)"
local BOOSTED = "Sidecar 120 Hz"
local function screensNow(...)
  env.screens = { ... }
  env.screensChanged()
end

-- A connect boosts Sidecar's display. sidecarctl ends the boost with the session, and
-- the next session's display gets a new one
s = boot()
s:start()
env.usb(event(IPAD, "added"))
fire()
env.screens = { SIDECAR }
lastTask():finish(0, "connected to Test iPad\n")
local boosting = lastTask()
check(argsOf(boosting) == "boost --hz 120" and boosting.running, "a connect boosts the Sidecar display, got " .. argsOf(boosting))
screensNow(BOOSTED)
check(boosting.running and #env.tasks == 2, "a mirrored Sidecar display keeps the one boost")
env.usb(event(IPAD, "removed"))
check(argsOf(lastTask()) == "disconnect" and boosting.running, "an unplug disconnects and leaves the boost to end with the session")
screensNow()
boosting:finish(0)
check(not lastAlert():find("60 Hz", 1, true), "a boost ending with its session says nothing")
screensNow(SIDECAR)
check(lastTask() ~= boosting and argsOf(lastTask()) == "boost --hz 120", "the next session is boosted afresh")
s:stop()

-- A successful connect clears a failed boost, since the session it failed on is gone
s = boot()
s:start()
s.boostFailed = true
env.usb(event(IPAD, "added"))
fire()
env.screens = { SIDECAR }
lastTask():finish(0, "connected to Test iPad\n")
check(argsOf(lastTask()) == "boost --hz 120", "a new session is boosted though the last boost failed")
s:stop()

-- A boost that fails because its session was replaced by a connect here is not
-- reported, and the new session is boosted
s = boot()
env.screens = { SIDECAR }
s:start()
local stale = lastTask()
check(argsOf(stale) == "boost --hz 120", "a boost starts on the session found at start")
env.usb(event(IPAD, "added"))
fire()
lastTask():finish(0, "connected to Test iPad\n")
alerts = #hs._log
stale:finish(4, "the Sidecar display did not take the mirror\n")
check(#hs._log == alerts, "its failure is not reported")
check(lastTask() ~= stale and argsOf(lastTask()) == "boost --hz 120" and not s.boostFailed, "and the new session gets a boost")
s:stop()

-- A session started by hand, with no cable, is boosted too
s = boot()
s:start()
check(#env.tasks == 0, "no Sidecar display at start, no boost")
screensNow(SIDECAR)
check(argsOf(lastTask()) == "boost --hz 120", "a Sidecar display appearing on its own is boosted")
screensNow(SIDECAR, BOOSTED)
check(#env.tasks == 1, "screen changes while the boost sets up start no second one")
s:stop()

-- A boost that fails says so, and one already running from before a reload does not
s = boot()
env.screens = { SIDECAR }
s:start()
lastTask():finish(2, "no Sidecar display appeared\n")
check(lastAlert() == "alert: Sidecar: staying at 60 Hz, no Sidecar display appeared", "a failed boost says why")
screensNow(SIDECAR)
check(#env.tasks == 1, "and is not retried within the same session")
screensNow()
screensNow(SIDECAR)
check(#env.tasks == 2, "the next session gets a new boost")
local alerts = #hs._log
lastTask():finish(7, "a boost is already running\n")
check(#hs._log == alerts, "exit code 7 is not reported")
s:stop()

-- A session left from before a reload is picked up without an alert, and boosted
s = boot()
env.attached = { IPAD }
s:start()
fire()
env.screens = { SIDECAR }
alerts = #hs._log
lastTask():finish(0, "already connected to Test iPad\n")
check(s.connected and #hs._log == alerts, "an existing session is taken over without an alert")
check(argsOf(lastTask()) == "boost --hz 120", "and boosted")
s:stop()

-- transport wireless forces Wi-Fi, and framerate is passed along
s = boot({ transport = "wireless", framerate = 240 })
s:start()
env.usb(event(IPAD, "added"))
fire()
check(argsOf(lastTask()) == "connect --connection wireless --framerate 240", "transport and framerate reach connect, got " .. argsOf(lastTask()))
s:stop()

-- retina adds --retina to the boost
s = boot({ retina = true })
env.screens = { SIDECAR }
s:start()
check(argsOf(lastTask()) == "boost --hz 120 --retina", "retina boosts in Retina mode, got " .. argsOf(lastTask()))
s:stop()

-- refreshRate off: no boost
s = boot({ refreshRate = false })
env.screens = { SIDECAR }
s:start()
env.usb(event(IPAD, "added"))
fire()
lastTask():finish(0, "connected to Test iPad\n")
check(argsOf(lastTask()) == "connect --connection wired", "with refreshRate off nothing is boosted")
s:stop()

-- stop ends the boost it holds, and asks sidecarctl to end one started before a reload
s = boot()
env.screens = { SIDECAR }
s:start()
boosting = lastTask()
s:stop()
check(boosting.terminated, "stop ends the boost it holds")
check(argsOf(lastTask()) == "boost --stop" and lastTask().running, "and runs boost --stop for any other")

print(failures == 0 and "ALL PASS" or (failures .. " FAILED"))
os.exit(failures == 0 and 0 or 1)
