-- Run: lua test/test_titlebartweaks.lua   (from the repo root)
package.path = "./test/?.lua;" .. package.path
local stub = require("stub_hs")

local failures = 0
local function check(cond, label)
  if not cond then failures = failures + 1 print("FAIL " .. label) else print("ok   " .. label) end
end

local function sameFrame(a, b)
  return a and b and a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h
end

local SCREEN = { x = 0, y = 25, w = 1440, h = 875 }

-- Fake windows ----------------------------------------------------------------

-- menus: set of "Window>Fill" style paths the app offers, all enabled
local function fakeApp(bundleID, menus)
  local app = { bundle = bundleID, menus = menus or {}, selected = {} }
  function app:bundleID() return self.bundle end
  function app:findMenuItem(path)
    if self.menus[table.concat(path, ">")] then return { enabled = true } end
    return nil
  end
  function app:selectMenuItem(path)
    local key = table.concat(path, ">")
    if not self.menus[key] then return false end
    table.insert(self.selected, key)
    local w = self.win
    if key == "Window>Fill" then
      w.prior, w.f = w.f, { x = SCREEN.x, y = SCREEN.y, w = SCREEN.w, h = SCREEN.h }
    elseif key == "Window>Zoom" then
      if w.zoomed then w.f, w.zoomed = w.prior, false
      else w.prior, w.f, w.zoomed = w.f, { x = SCREEN.x, y = SCREEN.y, w = SCREEN.w, h = SCREEN.h }, true end
    elseif key:find("Return to Previous Size", 1, true) then
      w.f = w.prior
    end
    return true
  end
  return app
end

local focused
local function fakeWindow(id, app, frame)
  local w = { _id = id, app = app, f = frame, full = false }
  app.win = w
  function w:id() return self._id end
  function w:application() return self.app end
  function w:frame() return { x = self.f.x, y = self.f.y, w = self.f.w, h = self.f.h } end
  function w:setFrame(f) self.f = { x = f.x, y = f.y, w = f.w, h = f.h } end
  function w:maximize() self.f = { x = SCREEN.x, y = SCREEN.y, w = SCREEN.w, h = SCREEN.h } end
  function w:screen() return { id = function() return 1 end, frame = function() return SCREEN end } end
  function w:focus() focused = self end
  function w:isFullScreen() return self.full end
  function w:setFullScreen(on) self.full = on end
  return w
end

-- Setup -----------------------------------------------------------------------

local calls, timers, posted, taps
-- Role reported for a point in the title band of the stub window, set per test
local titleRole = "AXWindow"
local APP_PID = 77

local function install()
  stub.install(".")
  for name in pairs(package.loaded) do
    if name == "TitleBarTweaks" or name == "CaddieCore" then
      package.loaded[name] = nil
    end
  end
  calls, timers, posted, taps = {}, {}, {}, {}
  focused = nil

  hs.timer.usleep = function() end
  -- WindowState reads the screens to record a natural frame
  hs.screen.allScreens = function() return { { id = function() return 1 end, frame = function() return SCREEN end } } end
  -- Queued rather than run inline, so code that stores the returned timer sees it
  hs.timer.doAfter = function(_, fn)
    local t = { fn = fn, running = true }
    function t:stop() self.running = false end
    table.insert(timers, t)
    return t
  end
  hs.window.focusedWindow = function() return focused end
  hs.window.list = function()
    return { { kCGWindowBounds = { X = 100, Y = 100, Width = 800, Height = 600 }, kCGWindowLayer = 0, kCGWindowOwnerPID = APP_PID } }
  end
  hs.keycodes = { map = { alt = 58 } }
  hs.eventtap.event.newKeyEvent = function(_, down)
    return { setProperty = function() end, post = function() table.insert(posted, down) end }
  end
  hs.eventtap.new = function(evTypes, fn)
    local tap = { fn = fn, running = false }
    function tap:start() self.running = true return self end
    function tap:stop() self.running = false return self end
    taps[evTypes[1]] = tap
    return tap
  end
  -- The green button of the window above sits at roughly (110..124, 105..119). The
  -- rest of the top 40 pt reports titleRole, and below that is content.
  local axWindow = {
    pid = function() return APP_PID end,
    attributeValue = function(_, attr)
      if attr == "AXRole" then return "AXWindow" end
      if attr == "AXSubrole" then return "AXStandardWindow" end
    end,
    asHSWindow = function() return focused end,
  }
  hs.axuielement = {
    systemElementAtPosition = function(p)
      table.insert(calls, "ax")
      local isButton = p.x >= 108 and p.x <= 126 and p.y >= 103 and p.y <= 121
      local role = isButton and "AXButton" or (p.y < 140 and titleRole or "AXTextArea")
      if role == "AXWindow" then return axWindow end
      return {
        pid = function() return APP_PID end,
        attributeValue = function(_, attr)
          if attr == "AXRole" then return role end
          if attr == "AXSubrole" then return isButton and "AXFullScreenButton" or nil end
          if attr == "AXWindow" then return axWindow end
        end,
      }
    end,
  }

  local Core = stub.loadSpoon("CaddieCore")
  local gb = stub.loadSpoon("TitleBarTweaks")
  -- Records every WindowState payload, in order
  Core.window():on("*", function(p) table.insert(calls, { "payload", p }) end, "Test")
  gb.Core = Core
  return gb, Core.window()
end

local function kinds()
  local out = {}
  for _, c in ipairs(calls) do out[#out + 1] = type(c) == "table" and c[1] or c end
  return table.concat(out, ",")
end

local function flushTimers()
  while #timers > 0 do
    local t = table.remove(timers, 1)
    if t.running then t.fn() end
  end
end

-- props maps property names, which the stub uses as property keys, to values
local function fakeEvent(evType, x, y, flags, props)
  local e = { flags = flags or {}, props = props or {} }
  function e:location() return { x = x, y = y } end
  function e:getType() return evType end
  function e:getFlags() return self.flags end
  function e:setFlags(f) self.flags = f end
  function e:getProperty(k) return self.props[k] or 0 end
  return e
end

-- Tests -----------------------------------------------------------------------

do
  local gb, state = install()
  local metrics = require("CaddieCore").metrics

  local start = { x = 100, y = 100, w = 800, h = 600 }
  local app = fakeApp("com.example.toggle", { ["Window>Move & Resize>Return to Previous Size"] = true })
  local win = fakeWindow(41, app, start)

  -- A window short of its screen maximizes to the screen frame, through WindowState
  local r = gb:toggle(win)
  check(r.status == "completed" and r.mode == "maximize" and r.method == "frame" and r.windowID == 41
    and r.app == "com.example.toggle", "toggle maximizes a window that is not maximized")
  check(sameFrame(r.previousFrame, start) and sameFrame(r.finalFrame, SCREEN) and sameFrame(win.f, SCREEN), "maximize frames")
  check(#app.selected == 0, "maximize uses no menu command")
  check(kinds() == "payload" and calls[1][2].action == "place" and calls[1][2].source == "titlebar"
    and calls[1][2].position == "maximize" and sameFrame(calls[1][2].screenFrame, SCREEN),
    "the payload is WindowState's place, from the title bar, with position and screen frame")
  check(state.undoStack:depth(41) == 1 and sameFrame(state.undoStack:peek(41), start), "undo recorded the previous frame")

  -- The next click restores the natural frame WindowState remembered
  calls = {}
  r = gb:toggle(win)
  check(r.status == "completed" and r.mode == "restore" and r.method == "frame" and sameFrame(win.f, start),
    "toggle on a window it maximized restores the remembered natural frame")
  check(calls[1][2].action == "restore" and calls[1][2].source == "titlebar", "the restore is WindowState's, from the title bar")

  -- Maximized by something else, with nothing remembered, a restore uses the app's
  -- menu. The fake app returns to `prior`, standing in for the size it remembers.
  win.f, win.prior = { x = SCREEN.x, y = SCREEN.y, w = SCREEN.w, h = SCREEN.h }, start
  focused = nil
  r = gb:toggle(win)
  check(r.status == "completed" and r.mode == "restore" and r.method == "menu" and sameFrame(win.f, start),
    "with no memory, a restore goes through Return to Previous Size")
  check(focused == win, "the menu restore focuses the window first")
  check(app.selected[#app.selected] == "Window>Move & Resize>Return to Previous Size", "restore menu path used")

  -- Within 20 pt of the screen frame counts as maximized
  win.f, win.prior = { x = 10, y = 35, w = 1420, h = 860 }, start
  r = gb:toggle(win)
  check(r.mode == "restore", "a frame within 20 pt of the screen counts as maximized")

  -- With no menu either, a restore goes to two thirds of the screen, centered
  local dapp = fakeApp("com.example.default", {})
  local dwin = fakeWindow(43, dapp, { x = 0, y = 25, w = 1440, h = 875 })
  r = gb:toggle(dwin)
  check(r.mode == "restore" and r.method == "default" and sameFrame(dwin.f, { x = 240, y = 171, w = 960, h = 583 }),
    "restore with no memory and no menu goes to two thirds centered")

  -- Another owner's transform on WindowState's restore supplies the frame
  local memo = { x = 300, y = 200, w = 500, h = 400 }
  local remove = state:use("restore", function(ctx) ctx.proposed.targetFrame = memo end,
    { kind = "transform", owner = "TestMemory", name = "restore" })
  win.f = { x = 0, y = 25, w = 1440, h = 875 }
  local selectedBefore = #app.selected
  r = gb:toggle(win)
  check(r.mode == "restore" and r.method == "frame" and sameFrame(win.f, memo) and #app.selected == selectedBefore,
    "a supplied restore frame is applied directly")
  remove()

  -- Exclusions veto
  calls = {}
  state.excluded = { ["com.example.blocked"] = true }
  local bapp = fakeApp("com.example.blocked", {})
  local bwin = fakeWindow(44, bapp, { x = 10, y = 30, w = 400, h = 300 })
  r = gb:toggle(bwin)
  check(r.status == "vetoed" and r.by == "WindowState" and r.reason == "excluded app com.example.blocked",
    "exclusions veto names owner and reason")
  check(sameFrame(bwin.f, { x = 10, y = 30, w = 400, h = 300 }), "vetoed window untouched")
  check(kinds() == "payload" and calls[1][2].windowID == 44 and calls[1][2].app == "com.example.blocked",
    "the veto payload names the window")
  state.excluded = nil

  -- No window
  focused = nil
  calls = {}
  r = gb:toggle(nil)
  check(r.status == "unchanged" and r.reason == "no window" and kinds() == "", "no window is unchanged and places nothing")

  -- Full screen
  local fwin = fakeWindow(45, fakeApp("com.example.full", {}), { x = 0, y = 25, w = 500, h = 500 })
  r = gb:fullscreen(fwin)
  check(r.status == "completed" and fwin.full and r.windowID == 45, "fullscreen enters full screen")
  r = gb:fullscreen(fwin)
  check(r.status == "unchanged", "fullscreen on a full screen window is unchanged")

  local snap = metrics.snapshot()
  check(snap["WindowState.place"] and snap["WindowState.restore"] and snap["WindowState.restore"].count >= 5,
    "toggles are timed as WindowState's place and restore")
  check(snap["TitleBarTweaks.fullscreen"] and snap["TitleBarTweaks.fullscreen"].count == 2, "TitleBarTweaks.fullscreen metric recorded")

  -- Hover and click, through the captured tap callbacks
  gb:start()
  local move, click, flags = taps.mouseMoved, taps.leftMouseDown, taps.flagsChanged
  check(move and move.running and click and click.running and flags and flags.running, "start runs three taps")

  calls = {}
  move.fn(fakeEvent("mouseMoved", 500, 400))
  flushTimers()
  check(#calls == 0 and #posted == 0, "move outside the button corner skips Accessibility")

  move.fn(fakeEvent("mouseMoved", 116, 112))
  move.fn(fakeEvent("mouseMoved", 117, 112))
  flushTimers()
  check(#calls == 1 and posted[1] == true, "hover over the button coalesces to one hit test and holds Option")

  move.fn(fakeEvent("mouseMoved", 600, 112))
  check(posted[2] == false, "leaving the corner releases Option without Accessibility")

  move.fn(fakeEvent("mouseMoved", 116, 112))
  flushTimers()
  check(posted[3] == true, "hover again holds Option")
  gb:stop()
  check(posted[4] == false and not move.running and not click.running, "stop releases Option and taps")

  gb:start()
  move, click = taps.mouseMoved, taps.leftMouseDown
  move.fn(fakeEvent("mouseMoved", 116, 112))
  flushTimers()
  local before = #posted
  hs.shutdownCallback()
  check(posted[before + 1] == false, "shutdown releases simulated Option")

  -- Plain click on the button maximizes, swallowing down and up
  local kwin = fakeWindow(46, fakeApp("com.example.click", {}), { x = 100, y = 100, w = 800, h = 600 })
  focused = kwin
  local swallowedDown = click.fn(fakeEvent("leftMouseDown", 116, 112))
  local swallowedUp = click.fn(fakeEvent("leftMouseUp", 116, 112))
  flushTimers()
  check(swallowedDown == true and swallowedUp == true and sameFrame(kwin.f, SCREEN), "plain click maximizes and is swallowed")

  -- Title-bar double-click toggles the same way, and a single click does nothing
  local twin = fakeWindow(47, fakeApp("com.example.title", { ["Window>Move & Resize>Return to Previous Size"] = true }),
    { x = 100, y = 100, w = 800, h = 600 })
  focused = twin
  local CLICK2 = { mouseEventClickState = 2 }
  check(click.fn(fakeEvent("leftMouseDown", 500, 110)) == false, "a single click on the title bar passes")
  click.fn(fakeEvent("leftMouseUp", 500, 110))
  local tDown = click.fn(fakeEvent("leftMouseDown", 500, 110, {}, CLICK2))
  local tUp = click.fn(fakeEvent("leftMouseUp", 500, 110, {}, CLICK2))
  flushTimers()
  check(tDown == true and tUp == true and sameFrame(twin.f, SCREEN), "title-bar double-click maximizes and is swallowed")
  -- The stub window list still places the window at (100, 100), so the same point is
  -- in its title band
  twin.prior = { x = 100, y = 100, w = 800, h = 600 }
  click.fn(fakeEvent("leftMouseDown", 500, 110, {}, CLICK2))
  click.fn(fakeEvent("leftMouseUp", 500, 110, {}, CLICK2))
  flushTimers()
  check(sameFrame(twin.f, { x = 100, y = 100, w = 800, h = 600 }), "a second title-bar double-click restores")

  for _, role in ipairs({ "AXToolbar", "AXGroup", "AXStaticText", "AXTabGroup" }) do
    titleRole = role
    twin.f = { x = 100, y = 100, w = 800, h = 600 }
    click.fn(fakeEvent("leftMouseDown", 500, 110, {}, CLICK2))
    click.fn(fakeEvent("leftMouseUp", 500, 110, {}, CLICK2))
    flushTimers()
    check(sameFrame(twin.f, SCREEN), "title-bar double-click on " .. role .. " toggles")
  end
  for _, role in ipairs({ "AXButton", "AXRadioButton", "AXTextField", "AXPopUpButton" }) do
    titleRole = role
    twin.f = { x = 100, y = 100, w = 800, h = 600 }
    local passed2 = click.fn(fakeEvent("leftMouseDown", 500, 110, {}, CLICK2))
    click.fn(fakeEvent("leftMouseUp", 500, 110, {}, CLICK2))
    flushTimers()
    check(passed2 == false and sameFrame(twin.f, { x = 100, y = 100, w = 800, h = 600 }),
      "double-click on a " .. role .. " in the title band passes")
  end
  titleRole = "AXWindow"
  twin.f = { x = 100, y = 100, w = 800, h = 600 }
  local below = click.fn(fakeEvent("leftMouseDown", 500, 160, {}, CLICK2))
  click.fn(fakeEvent("leftMouseUp", 500, 160, {}, CLICK2))
  flushTimers()
  check(below == false and sameFrame(twin.f, { x = 100, y = 100, w = 800, h = 600 }), "double-click below the title band passes")
  gb.titleBarDoubleClick = false
  local off = click.fn(fakeEvent("leftMouseDown", 500, 110, {}, CLICK2))
  click.fn(fakeEvent("leftMouseUp", 500, 110, {}, CLICK2))
  flushTimers()
  check(off == false, "titleBarDoubleClick = false leaves title-bar double-clicks alone")
  gb.titleBarDoubleClick = true

  -- Option-click passes through with Option stripped
  flags.fn(fakeEvent("flagsChanged", 0, 0, { alt = true }))
  local down = fakeEvent("leftMouseDown", 116, 112, { alt = true })
  local passed = click.fn(down)
  check(passed == false and down.flags.alt == nil, "Option-click passes through without Option")
  click.fn(fakeEvent("leftMouseUp", 116, 112, { alt = true }))
  gb:stop()

  do
    -- Window bounds are listed from a timer on hover and inside the tap on click
    local listCalls, windowX = 0, 1000
    hs.window.list = function()
      listCalls = listCalls + 1
      return { { kCGWindowBounds = { X = windowX, Y = 100, Width = 800, Height = 600 }, kCGWindowLayer = 0 } }
    end
    -- The cache is Core's, shared with every title-bar Spoon, so it outlives a stop
    require("CaddieCore").titlebar().bounds = nil
    gb:start()
    move, click, flags = taps.mouseMoved, taps.leftMouseDown, taps.flagsChanged
    flags.fn(fakeEvent("flagsChanged", 0, 0, {}))

    move.fn(fakeEvent("mouseMoved", 1500, 400))
    move.fn(fakeEvent("mouseMoved", 1501, 400))
    check(listCalls == 0, "move tap never lists windows itself")
    local pendingRefreshes = 0
    for _, t in ipairs(timers) do if t.fn == gb.onBoundsRefresh and t.running then pendingRefreshes = pendingRefreshes + 1 end end
    check(pendingRefreshes == 1, "a burst of moves schedules one bounds refresh")
    flushTimers()
    check(listCalls == 1, "bounds refreshed from the timer")

    -- The window moves into place under a cursor that then stops in its corner. The
    -- stopping move is judged against the old bounds, then again after the refresh.
    windowX = 100
    require("CaddieCore").titlebar().boundsAt = -1e15
    calls = {}
    local postedBefore = #posted
    move.fn(fakeEvent("mouseMoved", 116, 112))
    check(#posted == postedBefore and gb.hoverPoint == nil, "stale bounds miss the corner at first")
    flushTimers()
    check(listCalls == 2 and #posted == postedBefore + 1 and posted[#posted] == true,
      "after the refresh a cursor stopped in the corner gets its hover")

    -- Leaving is caught the same way when the window moves out from under the cursor
    windowX = 1000
    require("CaddieCore").titlebar().boundsAt = -1e15
    move.fn(fakeEvent("mouseMoved", 117, 112))
    flushTimers()
    check(posted[#posted] == false and not gb.hoverAlt, "a window moved away releases the hover after the refresh")

    windowX = 100
    local before = listCalls
    click.fn(fakeEvent("leftMouseDown", 600, 400))
    check(listCalls == before + 1, "click still lists windows inside the tap")
    click.fn(fakeEvent("leftMouseUp", 600, 400))

    require("CaddieCore").titlebar().boundsAt = -1e15
    move.fn(fakeEvent("mouseMoved", 500, 400))
    local pending
    for _, t in ipairs(timers) do if t.fn == gb.onBoundsRefresh then pending = t end end
    gb:stop()
    check(pending and not pending.running and gb.boundsTimer == nil and gb.lastMovePoint == nil,
      "stop cancels a pending bounds refresh")
    flushTimers()
  end
end

print(failures == 0 and "ALL PASS" or (failures .. " FAILED"))
os.exit(failures == 0 and 0 or 1)
