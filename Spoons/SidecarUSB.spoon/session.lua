-- Connecting and disconnecting. A connect runs after a short wait, since the iPad
-- shows up on USB before Sidecar can reach it, and is retried while it fails, which
-- also covers an iPad still locked when it is plugged in. One step runs at a time,
-- and a new plug or unplug cancels whatever is pending.

local part = ...
local launcher = part("launcher")

-- Failures a retry cannot fix, by sidecarctl's exit code. The rest are retried,
-- among them 8, an iPad not yet seen on USB, and 9, one not ready, which sidecarctl
-- reports without asking Sidecar, so no dialog comes of it.
local FINAL = {
  [1] = "sidecarctl rejected its arguments",
  [5] = "this Mac's Sidecar framework is unavailable",
  [6] = "more than one iPad reachable, set device",
}

-- Whether Sidecar's own display is listed, which it is only while nothing mirrors it.
-- Read from hs.screen rather than CaddieCore.screens(), whose cache may not be
-- cleared yet when the screen watcher calls this.
local function sidecarShowing()
  for _, screen in ipairs(hs.screen.allScreens()) do
    if (screen:name() or ""):find("^Sidecar Display") then return true end
  end
  return false
end

return function(obj)
  function obj:_notify(message)
    print(self.name .. ": " .. message)
    if self.alerts then hs.alert.show("Sidecar: " .. message, 2) end
  end

  -- A terminated task still calls back, so every callback checks it belongs to the
  -- current generation before acting
  function obj:_cancel()
    self.generation = (self.generation or 0) + 1
    if self.timer then self.timer:stop() end
    if self.task and self.task:isRunning() then self.task:terminate() end
    self.timer, self.task = nil, nil
  end

  -- The first connect after a replug fails inside Sidecar, which shows "Unable to
  -- Connect to “<name>”" through UserNotificationCenter while the retry connects.
  -- Only that dialog, for that device, is dismissed, and only when a connect here
  -- has failed. It can appear just after the failure is reported, so window creation
  -- is watched for a few seconds as well. A connect that never succeeds still ends
  -- in this Spoon's own alert.
  function obj:_dismissFailure(name)
    local title = "Unable to Connect to “" .. name .. "”"
    local function press(win)
      local matched, ok = false, nil
      for _, child in ipairs(win:attributeValue("AXChildren") or {}) do
        local role = child:attributeValue("AXRole")
        if role == "AXStaticText" and child:attributeValue("AXValue") == title then matched = true end
        if role == "AXButton" and child:attributeValue("AXTitle") == "OK" then ok = child end
      end
      if matched and ok then ok:performAction("AXPress") end
    end
    self:_stopDismissing()
    local app = hs.application.applicationsForBundleID("com.apple.UserNotificationCenter")[1]
    local ax = app and hs.axuielement.applicationElement(app)
    if not ax then return end
    for _, win in ipairs(ax:attributeValue("AXWindows") or {}) do press(win) end
    self.dismissWatch = hs.axuielement.observer.new(app:pid())
      :callback(function(_, win) press(win) end)
      :addWatcher(ax, "AXWindowCreated")
      :start()
    self.dismissTimer = hs.timer.doAfter(5, function() self:_stopDismissing() end)
  end

  function obj:_stopDismissing()
    if self.dismissWatch then self.dismissWatch:stop() end
    if self.dismissTimer then self.dismissTimer:stop() end
    self.dismissWatch, self.dismissTimer = nil, nil
  end

  function obj:_run(args, done)
    local generation = self.generation
    self.task = launcher.run(self.path, args, function(code, out)
      if generation ~= self.generation then return end
      self.task = nil
      done(code, out)
    end)
  end

  -- With no device, sidecarctl picks the one reachable iPad itself. The connection
  -- is always named, since sidecarctl's own default falls back to Wi-Fi.
  function obj:_args(command)
    local args = { command }
    if self.device then args[2] = self.device end
    if command == "connect" then
      args[#args + 1] = "--connection"
      args[#args + 1] = self.transport or "system"
      if self.framerate then
        args[#args + 1] = "--framerate"
        args[#args + 1] = tostring(self.framerate)
      end
    end
    return args
  end

  -- A boost follows Sidecar's display rather than the connects made here, so a
  -- session started from Control Center or System Settings is boosted too. It starts
  -- when Sidecar's own display shows, and sidecarctl ends it when the session ends.
  -- It runs for the whole session, so it is held apart from self.task. Exit code 0
  -- is a boost that ended with its session, and 7 one still running from before a
  -- reload.
  function obj:_syncBoost()
    if not self.refreshRate or not self.path then return end
    -- A failed boost is not retried until the next session, since setting it up and
    -- tearing it down changes the screens, which would start it again at once
    if not sidecarShowing() then
      self.boostFailed = nil
      return
    end
    if not self.boostFailed and not (self.boostTask and self.boostTask:isRunning()) then
      local task
      local args = { "boost", "--hz", tostring(self.refreshRate) }
      if self.retina then args[#args + 1] = "--retina" end
      local session = self.session
      task = launcher.run(self.path, args, function(code, out)
        if self.boostTask ~= task then return end
        self.boostTask = nil
        if code == 0 or code == 7 then return end
        -- A boost caught by its session being replaced says nothing about the new one
        if session ~= self.session then return self:_syncBoost() end
        self.boostFailed = true
        self:_notify("staying at 60 Hz, " .. out:match("^%s*(.-)%s*$"))
      end)
      self.boostTask = task
    end
  end

  function obj:_stopBoost()
    local task = self.boostTask
    self.boostTask = nil
    if task and task:isRunning() then task:terminate() end
  end

  function obj:_connect(attempt)
    self.timer = nil
    self:_run(self:_args("connect"), function(code, out)
      if code == 0 then
        self.connected = true
        -- A new session, so a boost that failed on the one it replaced may try again
        self.session = (self.session or 0) + 1
        self.boostFailed = nil
        self:_syncBoost()
        local message = out:match("^%s*(.-)%s*$")
        -- A session from before a reload is picked up on every reload, so quietly
        if message:find("^already") then return print(self.name .. ": " .. message) end
        return self:_notify(message)
      end
      local device = out:match("connect to (.-) failed:")
      if device then self:_dismissFailure(device) end
      if FINAL[code] or attempt >= self.attempts then
        return self:_notify(FINAL[code] or ("could not connect (exit code " .. tostring(code) .. ")"))
      end
      self.timer = hs.timer.doAfter(self.retryDelay, function() self:_connect(attempt + 1) end)
    end)
  end

  function obj:_plugged()
    self:_cancel()
    self.timer = hs.timer.doAfter(self.connectDelay, function() self:_connect(1) end)
  end

  -- Disconnects even when nothing here connected it, since a wired session left
  -- behind does not fall back to wireless on its own. With no session to end,
  -- sidecarctl also exits 0, saying "not connected", which is not worth an alert.
  function obj:_unplugged()
    self:_cancel()
    self.connected = nil
    self:_run(self:_args("disconnect"), function(code, out)
      local message = out:match("^%s*(.-)%s*$")
      if code == 0 and message:find("^disconnected") then self:_notify(message) end
    end)
  end
end
