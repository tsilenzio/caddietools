-- Smooth scrolling: a flipped wheel notch is swallowed and replayed as a glide of
-- small continuous events, in the manner of Mos (github.com/Caldis/Mos). The glide
-- model is explained above `_glideTick`.

local part = ...
local E = part("scroll/events")

local now = hs.timer.absoluteTime

return function(obj)
  -- Adds one notch to the distance still to scroll and starts the glide timer if it
  -- is not running. Notches in the same direction accumulate, so a fast spin builds
  -- speed. A notch against the current direction drops what is left, as Mos does,
  -- rather than spending a few frames cancelling it out.
  function obj:_addToGlide(event, size)
    local s = self.smooth
    local magnitude = math.max(math.abs(size), s.minStep) * s.speed
    local distance = size < 0 and -magnitude or magnitude
    -- A notch aimed at another app starts a fresh glide there
    local pid = event:getProperty(E.TARGET_PID)
    if self.pending * distance < 0 or pid ~= self.glidePid then self.pending, self.carry = 0, 0 end
    self.glidePid = pid
    self.pending = self.pending + distance
    -- The newest notch is the template, so posted events carry its modifier flags
    self.template = event:copy()
    if not self.glideTimer then
      self.lastTick = now()
      self.glideTimer = hs.timer.doEvery(1 / self:_tickRate(), self.onGlideTick)
    end
  end

  -- The refresh rate of the screen under the cursor, read once per glide. Ticking
  -- faster than the screen redraws is wasted work, and ticking slower leaves some
  -- redraws with no movement. A glide that crosses screens keeps its first rate,
  -- which the time-based model below tolerates.
  function obj:_tickRate()
    local s = self.smooth
    local screen = hs.mouse.getCurrentScreen()
    local mode = screen and screen:currentMode()
    local hz = mode and mode.freq or 0
    -- Some displays report 0 Hz, which means unknown
    if hz <= 0 then hz = s.fallbackHz end
    return math.min(math.max(hz, s.minHz), s.maxHz)
  end

  -- One glide step. The model is the delta-time pattern from game loops: each tick
  -- measures how much real time passed and moves by an amount derived from that, so
  -- the glide covers the same distance over the same time at any tick rate.
  --
  -- State: `pending` is the distance in points not yet scrolled. Each tick:
  --
  --   dt    = seconds since the previous tick, capped at maxDt
  --   alpha = 1 - exp(-dt / tau)
  --   move  = pending * alpha
  --   pending = pending - move
  --
  -- This is exponential decay of `pending` toward zero: after t seconds of ticks,
  -- pending(t) = pending(0) * exp(-t / tau), whatever the individual dt values were,
  -- because exp(-a) * exp(-b) = exp(-(a + b)). Scroll speed is proportional to the
  -- distance left, so a glide starts fast and eases out. `tau` is the time constant:
  -- after tau seconds about 63% of a notch has scrolled, after 3 tau about 95%.
  --
  -- Why this form. Mos moves a fixed fraction of the remaining distance on every
  -- display frame: move = remaining * k, with k = 0.085 by default. That is the
  -- same decay with dt assumed to be one frame, so its feel depends on refresh rate.
  -- The equivalent tau is -frameTime / ln(1 - k): about 188 ms at 60 Hz, 94 ms at
  -- 120 Hz, 47 ms at 240 Hz, 34 ms at 330 Hz. Writing alpha from the measured dt
  -- keeps tau constant on every display. It also makes a late tick harmless, which
  -- matters here because Hammerspoon runs Lua, timers, and every event tap on one
  -- thread, so ticks arrive late whenever something else is running.
  --
  -- Why not a fixed-timestep accumulator, the other common game-loop pattern. That
  -- pattern keeps a numerical simulation stable by advancing it in equal steps. The
  -- exponential has an exact closed form for any dt, so there is nothing to keep
  -- stable and the accumulator would only add code.
  --
  -- Why dt is capped. After a long stall, such as a slow window operation on the
  -- main thread, an uncapped dt makes alpha close to 1 and the rest of the glide
  -- lands in one jump. The cap turns the stall into a brief slowdown instead.
  --
  -- Why `carry`. Hammerspoon accepts only whole numbers for the point delta, which
  -- is the field apps read for continuous scrolling. Each tick posts the whole-point
  -- part of the accumulated movement and keeps the fraction for the next tick, so
  -- no distance is lost to rounding.
  --
  -- The glide ends when `pending` falls below `settle` points. What is left, pending
  -- plus carry, goes out rounded as one last event, since a carry under one point
  -- would otherwise never post. The timer is then stopped and released, so an idle
  -- wheel costs nothing.
  function obj:_glideTick()
    local s = self.smooth
    local t = now()
    local dt = math.min((t - self.lastTick) / 1e9, s.maxDt)
    self.lastTick = t
    local move = self.pending * (1 - math.exp(-dt / s.tau))
    self.pending = self.pending - move
    self.carry = self.carry + move
    -- Truncated toward zero so the fraction kept in carry has the glide's sign
    local whole = self.carry < 0 and math.ceil(self.carry) or math.floor(self.carry)
    if whole ~= 0 then
      self.carry = self.carry - whole
      self:_post(whole)
    end
    if math.abs(self.pending) < s.settle then
      local rest = self.pending + self.carry
      rest = rest < 0 and math.ceil(rest - 0.5) or math.floor(rest + 0.5)
      if rest ~= 0 then self:_post(rest) end
      self:_endGlide()
    end
  end

  -- Each event is stamped with the cursor's current position before posting.
  -- Hammerspoon's `event:post()` is CGEventPost at the session tap, which moves the
  -- cursor to the event's location, so a location copied from the notch pinned the
  -- cursor there for the whole glide. `event:post(app)` would avoid that, but in
  -- Hammerspoon 1.1.1 it goes through the deprecated GetProcessForPID and
  -- CGEventPostToPSN, and on macOS 27 those events never arrived. Mos posts with
  -- CGEventPostToPid, which Hammerspoon does not expose. Posting at the cursor also
  -- means a glide follows the cursor into whatever window it moves over.
  --
  -- `event:post()` also sleeps 1 ms on the main thread after every post, so a glide
  -- ticking at 240 Hz spends about a quarter of the main thread in that sleep.
  function obj:_post(points)
    local e = self.template:copy()
    e:location(hs.mouse.absolutePosition())
    e:setProperty(E.USER_DATA, E.GLIDE_MARK)
    e:setProperty(E.CONTINUOUS, 1)
    -- Writing the line delta makes macOS recompute the point and fixed-point deltas,
    -- so it goes first and they are written after it. A continuous event of a few
    -- points is under one line, which is what a trackpad reports too.
    e:setProperty(E.DELTA, 0)
    e:setProperty(E.POINT, points)
    e:setProperty(E.FIXED, points / 10)
    e:post()
  end

  function obj:_endGlide()
    if self.glideTimer then self.glideTimer:stop() end
    self.glideTimer, self.template, self.glidePid = nil, nil, nil
    self.pending, self.carry = 0, 0
  end
end
