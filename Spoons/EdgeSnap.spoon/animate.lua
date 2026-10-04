-- One 60 Hz timer drives every animation and exists only while something moves.
-- Each canvas has at most one animation, and a new one starts from wherever the last
-- one left it.

local rect = require("CaddieCore").rect

return function(obj)
  -- The geometry curve Rectangle uses for its footprint, a cubic bezier with control
  -- points (0.1, 0.9) and (0.2, 1), solved for y at x by bisection
  local function decelerate(x)
    if x <= 0 or x >= 1 then return math.max(0, math.min(1, x)) end
    local function bezier(t, a, b)
      local u = 1 - t
      return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
    end
    local lo, hi = 0, 1
    for _ = 1, 30 do
      local t = (lo + hi) / 2
      if bezier(t, 0.1, 0.2) < x then lo = t else hi = t end
    end
    return bezier((lo + hi) / 2, 0.9, 1)
  end

  -- Rectangle's fade curve, a cubic that decelerates to rest
  local function easeOut(t)
    t = math.max(0, math.min(1, t))
    return t * (3 + t * (t - 3))
  end

  local function lerp(a, b, k) return a + (b - a) * k end

  local function lerpRect(a, b, k)
    return { x = lerp(a.x, b.x, k), y = lerp(a.y, b.y, k), w = lerp(a.w, b.w, k), h = lerp(a.h, b.h, k) }
  end

  -- Steps anim.canvas toward anim.frame, when given, and anim.alpha. Each canvas has
  -- at most one animation, and a new one starts from wherever the last one left it.
  -- The 60 Hz timer exists only while an animation runs.
  function obj:_animate(anim)
    local c = anim.canvas
    if anim.frame then anim.fromFrame = anim.fromFrame or rect(c:frame()) end
    anim.fromAlpha = c:alpha()
    anim.start = hs.timer.absoluteTime()
    self.anims[c] = anim
    if not self.animTimer then
      self.animTimer = hs.timer.new(1 / 60, self.onAnimTick)
      self.animTimer:start()
    end
    self:_animTick()
  end

  function obj:_animTick()
    local now = hs.timer.absoluteTime()
    for c, a in pairs(self.anims) do
      local elapsed = (now - a.start) / 1e9
      local grow = a.grow > 0 and elapsed / a.grow or 1
      local fade = a.fade > 0 and elapsed / a.fade or 1
      if a.frame then c:frame(lerpRect(a.fromFrame, a.frame, decelerate(math.min(1, grow)))) end
      if a.follow and not self:_followStep(c, a, now) then grow = 0 end
      c:alpha(lerp(a.fromAlpha, a.alpha, easeOut(fade)))
      if grow >= 1 and fade >= 1 then
        self.anims[c] = nil
        if a.done then a.done() end
      end
    end
    if next(self.anims) == nil then self:_stopAnim() end
  end

  -- One frame of the follow: the canvas covers its share of the way to where the
  -- panel now is. Returns true once it has arrived. The position is carried on the
  -- animation rather than read back, since a canvas on a 1x screen rounds its frame to
  -- whole points and a step under one point would round back and never arrive.
  function obj:_followStep(c, a, now)
    local goal = a.follow.canvasFrame
    if not a.x then
      local f = c:frame()
      a.x, a.y = f.x, f.y
    end
    local dt = (now - (a.last or a.start)) / 1e9
    a.last = now
    local tau = a.tau or self.pickerFollow
    local k = tau > 0 and 1 - math.exp(-dt / tau) or 1
    local x, y = a.x + (goal.x - a.x) * k, a.y + (goal.y - a.y) * k
    a.x, a.y = x, y
    if math.abs(goal.x - x) < 0.5 and math.abs(goal.y - y) < 0.5 then
      c:frame({ x = goal.x, y = goal.y, w = goal.w, h = goal.h })
      return true
    end
    c:frame({ x = x, y = y, w = goal.w, h = goal.h })
    return false
  end

  function obj:_stopAnim()
    if self.animTimer then self.animTimer:stop() end
    self.animTimer = nil
    self.anims = {}
  end
end
