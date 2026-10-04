-- Reversed scrolling for notched mouse wheels. Only events that report
-- scrollWheelEventIsContinuous as 0 are flipped, so trackpads and Magic Mouse keep
-- macOS Natural Scrolling.

local part = ...
local E = part("scroll/events")

local now = hs.timer.absoluteTime

return function(obj)
  -- Burst counts are totals minus the totals captured when the burst began, so the
  -- hot path increments one set of counters
  function obj:_summarize()
    self.summaryTimer = nil
    local endedAt = now()
    self:emit("summary", function()
      return {
        wheelEvents = self.wheelEvents - self.burstWheel,
        continuousEvents = self.continuousEvents - self.burstContinuous,
        flipped = self.flipped - self.burstFlipped,
        intervalS = (endedAt - self.burstStart) / 1e9,
      }
    end)
    -- Hammerspoon 1.1.1 re-enables a tap that macOS disabled for a timeout, but not
    -- one disabled for user input. A disabled tap delivers nothing, so a watchdog would
    -- need a repeating timer. This check rides the summary timer instead, at no idle
    -- cost, and catches a disable that lands during a burst.
    local tap = self.tap
    if tap and not tap:isEnabled() then
      print(self.name .. ": tap was disabled, restarting")
      tap:start()
    end
  end

  function obj:process(event)
    -- Glide events pass untouched. Their target process is not checked: macOS keeps
    -- reporting the app a glide started in even while it delivers to the app under
    -- the cursor, so a cross-app stop needs posting to a process (a native module) or
    -- a check against the window's bounds.
    if event:getProperty(E.USER_DATA) == E.GLIDE_MARK then return false end
    if not self.summaryTimer and self.onSummaryTimer then
      self.burstWheel, self.burstContinuous, self.burstFlipped = self.wheelEvents, self.continuousEvents, self.flipped
      self.burstStart = now()
      self.summaryTimer = hs.timer.doAfter(self.summaryDelay, self.onSummaryTimer)
    end
    if event:getProperty(E.CONTINUOUS) ~= 0 then
      self.continuousEvents = self.continuousEvents + 1
      return false
    end
    self.wheelEvents = self.wheelEvents + 1
    -- Setting one delta makes macOS recompute the others, so all three are read
    -- before any is written. Interleaved get/set left them disagreeing and apps saw
    -- no flip.
    local delta, point, fixed = event:getProperty(E.DELTA), event:getProperty(E.POINT), event:getProperty(E.FIXED)
    event:setProperty(E.DELTA, -delta)
    event:setProperty(E.POINT, -point)
    event:setProperty(E.FIXED, -fixed)
    self.flipped = self.flipped + 1
    -- Only purely vertical notches glide. Swallowing an event that also carries
    -- horizontal motion would drop that motion.
    if self.smooth.enabled
      and event:getProperty(E.DELTA_X) == 0 and event:getProperty(E.POINT_X) == 0 then
      -- Mos's order of preference for the notch's size: points, then fixed-point
      -- lines, then whole lines
      local size = (point ~= 0 and point) or (fixed ~= 0 and fixed) or delta
      if size ~= 0 then
        self:_addToGlide(event, -size)
        return true
      end
    end
    return false
  end
end
