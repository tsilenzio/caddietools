--- === SidecarUSB ===
---
--- Starts Sidecar on an iPad when it is plugged in by USB, and ends it when it is
--- unplugged, though Sidecar could carry on wirelessly. `transport` forces the
--- session over the cable or over Wi-Fi.
---
--- Sidecar renders at 60 Hz. With `refreshRate` set, the session's display is
--- mirrored onto a virtual display running at that rate for as long as the session
--- lasts, so a ProMotion iPad shows 120 Hz. That follows Sidecar's display rather
--- than the cable, so a wireless session started by hand from Control Center or
--- System Settings is mirrored too, though only a plug starts one. macOS gives the
--- virtual display its own place in System Settings > Displays, where it can be
--- arranged like any other.
---
--- Needs sidecarctl installed with Homebrew, since macOS has no public API for
--- Sidecar. Without it the Spoon says so in the console and does nothing. sidecarctl
--- uses private frameworks, so a macOS update can break it.

local Core = require("CaddieCore")
local part = Core.part
local launcher = part("launcher")

local obj = {}
obj.__index = obj

obj.name = "SidecarUSB"
obj.version = "0.1.0"

-- Path to sidecarctl, where Homebrew links it on Apple silicon
obj.helperPath = "/opt/homebrew/bin/sidecarctl"
-- The iPad's UUID or name as Sidecar knows it, from `sidecarctl devices`. Needed
-- only when more than one iPad is reachable.
obj.device = nil
-- "wired" or "wireless" to force the session over one, "prefer-wired" for the cable
-- with Wi-Fi when it fails, or nil to let Sidecar choose. A session already running
-- over another, such as a wireless one when the cable goes in, is replaced. Once
-- wired, a session does not fall back to wireless on its own.
obj.transport = "wired"
-- Frames a second Sidecar streams at, or nil for its own choice of 60. Applies only
-- to sessions started here.
obj.framerate = nil
-- Seconds after the iPad appears on USB before the first try
obj.connectDelay = 2
-- Tries before giving up, and seconds between them. Ten tries 3 s apart leave about
-- half a minute to unlock the iPad.
obj.attempts = 10
obj.retryDelay = 3
-- Connect at start when an iPad is already plugged in
obj.connectOnStart = true
-- Show an alert on connect, disconnect, and failure, besides the console line
obj.alerts = true
-- Refresh rate for the session, nil or false for Sidecar's own 60 Hz
obj.refreshRate = 120
-- With refreshRate set, also switch Sidecar's display to its Retina mode at the same
-- size, twice the pixels each way, for sharper text at four times the pixels to
-- render and encode
obj.retina = false

part("session")(obj)

-- An iPad on USB. Apple's vendor ID is 0x05AC.
function obj.isIPad(device)
  return device.vendorID == 0x05AC and (device.productName or ""):find("iPad", 1, true) ~= nil
end

function obj:init()
  Core.component(self)
  return self
end

function obj:_onUSB(event)
  if not self.isIPad(event) then return end
  if not self.path then
    self:_notify("sidecarctl not installed")
    return
  end
  if event.eventType == "added" then self:_plugged() elseif event.eventType == "removed" then self:_unplugged() end
end

function obj:start()
  if self.scope then return self end
  self.scope = Core.scope(self.name)
  self.path = launcher.find(self.helperPath)
  if not self.path then print(self.name .. ": sidecarctl not installed, so nothing will connect") end
  self.scope:add(function() self:_cancel() end, "connect timer and task")
  self.scope:add(function() self:_stopBoost() end, "boost")
  self.scope:add(function() self:_stopDismissing() end, "dialog watch")
  self.screenWatcher = self.scope:watcher(hs.screen.watcher.new(function() self:_syncBoost() end), "screen watcher")
  self:_syncBoost()
  -- Held on self, since a watcher with no reference is garbage collected
  self.watcher = self.scope:watcher(hs.usb.watcher.new(function(e) self:_onUSB(e) end), "USB watcher")
  if self.connectOnStart and self.path then
    for _, device in ipairs(hs.usb.attachedDevices() or {}) do
      if self.isIPad(device) then
        self:_plugged()
        break
      end
    end
  end
  return self
end

function obj:stop()
  if self.scope then self.scope:close() end
  -- A boost started before a reload is not held here, so sidecarctl ends whichever
  -- one is running
  if self.path and self.refreshRate then
    self.stopTask = launcher.run(self.path, { "boost", "--stop" }, function() self.stopTask = nil end)
  end
  self.scope, self.watcher, self.screenWatcher, self.path = nil, nil, nil, nil
  return self
end

return obj
