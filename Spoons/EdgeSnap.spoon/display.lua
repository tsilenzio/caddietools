-- What the drag shows at an edge: confirming the window really moved, then the
-- preview and the panel, gliding the panel after the cursor and into a corner's L

local part = ...
local Core = require("CaddieCore")
local panel = part("panel/init")
local MOVED_MIN = part("constants").MOVED_MIN
local windows = Core.titlebar().windows

return function(obj)
  -- Starts the panel easing after the cursor, unless it already is
  function obj:_follow()
    self.followTimer = nil
    local target = self.target
    if target then target.followed = false end
    if not self.pickerShown or not target or target.picker ~= self.pickerDrawn then return end
    local running = self.anims[self.picker]
    if running and running.follow then return end
    self:_animate({ canvas = self.picker, follow = target.picker, alpha = 1, grow = 0, fade = self.previewFadeIn })
  end

  -- Shows or hides the preview for the edge the cursor is at now. The window is
  -- confirmed to be moving with the mouse the first time it reaches an edge.
  function obj:_zone()
    self.zoneTimer = nil
    local target = self.target
    if not target or not target.zone then
      self:_hidePreview()
      self:_hidePicker()
      return
    end
    if not target.confirmed then
      local now = windows.boundsOf(target.id)
      local s = target.start
      if not now or (math.abs(now.x - s.x) < MOVED_MIN and math.abs(now.y - s.y) < MOVED_MIN) then return end
      target.confirmed = true
    end
    local extra = target.seam and self.seamTween or 0
    self:_showPreview(target.zone.frame, target.position, target.edgePoint, extra)
    if target.picker then
      self:_drawPicker(target.picker, panel.indexOf(target.picker, target.position))
      if not self.pickerShown then
        self.pickerShown = true
        if not self.anims[self.picker] then self.picker:alpha(0) end
        self.picker:show()
        self:_animate({ canvas = self.picker, alpha = 1, grow = 0, fade = self.previewFadeIn + extra })
      end
    else
      self:_hidePicker()
    end
  end

  -- Draws `picker` with cell `hovered` lit. The same panel redrawn keeps the canvas
  -- where the follow has it and lets the follow carry on. A different panel jumps to
  -- its own spot and drops any follow.
  function obj:_drawPicker(picker, hovered)
    local c = self.picker
    local morph = self.target and self.target.morph
    if morph and morph.to == picker and not morph.arrived then return self:_drawMorph(morph, hovered) end
    local same = self.pickerShown and self.pickerDrawn == picker
    panel.render(c, picker, hovered, same)
    local running = self.anims[c]
    if same then
      self.pickerDrawn = picker
      self:_follow()
      return
    end
    self.pickerDrawn = picker
    -- A panel split off an L starts where its arm was and eases on after the cursor
    local from = picker.drawFrom
    picker.drawFrom = nil
    if from and self.pickerShown then
      c:frame(from)
      if running and running.follow then
        running.follow, running.done = picker, nil
        return
      end
      self:_animate({ canvas = c, follow = picker, alpha = 1, grow = 0, fade = self.previewFadeIn })
      return
    end
    if running and running.follow then
      self:_animate({ canvas = c, alpha = 1, grow = 0, fade = self.previewFadeIn })
    end
  end

  -- Faded by _animate rather than hs.canvas's own show and hide fades. A hide fade
  -- interrupted by a quick return to the edge left the panel at alpha 0 for good.
  function obj:_hidePicker()
    if not self.picker or not self.pickerShown then return end
    self.pickerShown, self.pickerDrawn = false, nil
    self:_animate({ canvas = self.picker, alpha = 0, grow = 0, fade = self.previewFadeOut, done = function()
      if self.picker and not self.pickerShown then self.picker:hide() end
    end })
  end

  -- Keeps drawing the straight panel, with the L's selection lit where it has that
  -- cell, while it glides into its place in the L. On arrival the L is drawn over the
  -- same spot.
  function obj:_drawMorph(morph, hovered)
    local c, from = self.picker, morph.from
    local lit = hovered and panel.indexOf(from, morph.to.cells[hovered].position)
    local same = self.pickerShown and self.pickerDrawn == from
    panel.render(c, from, lit, same)
    self.pickerDrawn = from
    local function arrive()
      morph.arrived = true
      local target = self.target
      if target and target.morph == morph and self.pickerShown then
        panel.render(c, morph.to, panel.indexOf(morph.to, target.position))
        self.pickerDrawn = morph.to
      end
    end
    -- The magnet's own glide may already be carrying the panel, and arriving ends it
    local running = self.anims[c]
    if running and running.follow == from then
      running.done, running.tau = arrive, self.cornerPull
      return
    end
    self:_animate({ canvas = c, follow = from, tau = self.cornerPull, alpha = 1, grow = 0, fade = self.previewFadeIn,
      done = arrive })
  end
end
