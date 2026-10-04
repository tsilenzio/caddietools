--- === MouseTweaks ===
---
--- Mouse behavior macOS does not offer on its own. For now that is scrolling
--- (TKT-003): notched mouse wheels scroll reversed while trackpads and Magic Mouse
--- keep Natural Scrolling, and with `smooth.enabled` a wheel notch glides instead of
--- jumping, in the manner of Mos.
---
--- The scroll tap is a plain callback rather than a Core action, since it runs for
--- every wheel event. Each burst of scrolling ends in one `summary` event.

local Core = require("CaddieCore")
local part = Core.part

local obj = {}
obj.__index = obj

obj.name = "MouseTweaks"
obj.version = "0.3.0"

-- A scroll summary goes out this many seconds after the first event of a burst
obj.summaryDelay = 10

-- Smooth scrolling for wheel notches. The model behind these values is explained
-- above `_glideTick` in scroll/smooth.lua.
obj.smooth = {
  enabled = true,
  -- A notch scrolls at least minStep points, times speed. Both are Mos's defaults.
  minStep = 33.6,
  speed = 2.7,
  -- Seconds for about 63% of a notch to scroll. Mos's default feel on a 120 Hz
  -- display works out to about 0.094.
  tau = 0.09,
  -- Longest tick gap the glide honors, in seconds, so a stall slows the glide
  -- instead of jumping it
  maxDt = 0.04,
  -- Points left at which the glide stops
  settle = 0.5,
  -- Tick rate follows the screen under the cursor, clamped to this range. maxHz
  -- leaves room for 330 Hz displays.
  fallbackHz = 120,
  minHz = 60,
  maxHz = 360,
}

part("scroll/direction")(obj)
part("scroll/smooth")(obj)

local SCROLL_WHEEL = hs.eventtap.event.types.scrollWheel

function obj:init()
  Core.component(self)
  self.wheelEvents, self.continuousEvents, self.flipped = 0, 0, 0
  self.pending, self.carry = 0, 0
  return self
end

function obj:stats()
  return { wheelEvents = self.wheelEvents, continuousEvents = self.continuousEvents, flipped = self.flipped }
end

function obj:start()
  if self.scope then return self end
  self.scope = Core.scope(self.name)
  -- Built once here so arming a timer allocates no closure
  self.onSummaryTimer = function() self:_summarize() end
  self.onGlideTick = function() self:_glideTick() end
  self.scope:add(function()
    if self.summaryTimer then self.summaryTimer:stop() end
    self:_endGlide()
    self.summaryTimer, self.onSummaryTimer, self.onGlideTick = nil, nil, nil
  end, "summary and glide timers")
  -- Held on self, since a tap with no reference is garbage collected
  self.tap = self.scope:eventtap({ SCROLL_WHEEL }, function(e) return self:process(e) end, "scroll tap")
  return self
end

function obj:stop()
  if self.scope then self.scope:close() end
  self.scope, self.tap = nil, nil
  return self
end

return obj
