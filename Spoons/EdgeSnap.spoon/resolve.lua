-- Working out the placement for the cursor during a drag: the zone, the panel's
-- selection, the magnet, and the line becoming a corner's L

local part = ...
local panel = part("panel/init")
local constants = part("constants")
local PIN_SLACK, PICKER_SIDES, PICKER_CORNERS = constants.PIN_SLACK, constants.PICKER_SIDES, constants.PICKER_CORNERS

return function(obj)
  -- Works out the placement for the cursor at p and records it on the target. A
  -- corner zone opens the L for that corner with the corner cell selected. Otherwise
  -- an open panel's strips decide, and leaving them closes it. Returns true on a change.
  function obj:_resolve(target, p)
    local picker = target.picker
    local z, pos, seam = self:_zoneAt(p, target.down.y - target.start.y + PIN_SLACK)
    if seam and self.seamDelay > 0 and not target.seamReady then
      self:_holdSeam(target, p)
      z, pos = nil, nil
    elseif not seam then
      target.seamReady = false
      self:_releaseSeam()
    end
    local zone, position = nil, nil
    if self.edgePicker and PICKER_CORNERS[pos] and not self:_approaching(target, picker, z, pos, p) then
      if not (picker and picker.corner == pos and picker.zone == z) then
        local from = picker
        picker = panel.layoutCorner(pos, z.frame, z.full)
        picker.zone = z
        -- A straight panel on one of this L's edges glides on into its place in the L,
        -- and the L is drawn once it gets there
        if from and not from.corner and from.zone == z and panel.alignTo(from, picker) then
          target.morph = { from = from, to = picker }
        end
      end
      zone, position = z, picker.cells[panel.hit(picker, p) or picker.shared].position
      picker.seam = picker.seam or seam
    elseif picker and not picker.corner and panel.inStrip(picker, p) then
      -- Within the panel's length its cells select. Past either end the edge's own
      -- placement does, and beyond edgeZone the panel is pulled along behind the cursor.
      local i = panel.hit(picker, p)
      if not i then
        target.followed = panel.magnet(picker, p, self.edgeZone) or target.followed
        i = 2
      end
      zone, position, seam = picker.zone, picker.cells[i].position, picker.seam
    else
      local i = picker and panel.hit(picker, p)
      local arm = not i and picker and picker.corner and self.edgePicker and panel.armAt(picker, p)
      if i then
        zone, position, seam = picker.zone, picker.cells[i].position, picker.seam
      elseif arm then
        -- Leaving an L along one arm keeps that arm where it is as a straight panel,
        -- drops the other, and lets the magnet carry on from there
        local line = panel.layout(arm.side, picker.zone.frame, picker.zone.full, p)
        panel.alignTo(line, picker)
        line.zone, line.seam = picker.zone, picker.seam
        line.drawFrom = { x = line.canvasFrame.x, y = line.canvasFrame.y, w = line.canvasFrame.w, h = line.canvasFrame.h }
        panel.magnet(line, p, self.edgeZone)
        picker = line
        zone, position, seam = line.zone, line.cells[panel.hit(line, p) or 2].position, line.seam
      else
        zone, position, picker = z, pos, nil
        local side = self.edgePicker and PICKER_SIDES[pos]
        if side then
          picker = panel.layout(side, z.frame, z.full, p)
          picker.zone, picker.seam = z, seam
        end
      end
    end
    target.seam = seam
    if target.morph and target.morph.to ~= picker then target.morph = nil end
    if zone == target.zone and position == target.position and picker == target.picker then return false end
    target.zone, target.position, target.picker = zone, position, picker
    target.edgePoint = p
    return true
  end

  -- True while a straight panel on one of corner `pos`'s edges is still following the
  -- cursor toward it and has not come within cornerSnap of it, so the corner zone
  -- leaves it be. The magnet is applied here so the distance is the one after the pull.
  function obj:_approaching(target, picker, z, pos, p)
    if not picker or picker.corner or picker.zone ~= z or not panel.inStrip(picker, p) then return false end
    if not panel.hit(picker, p) then
      target.followed = panel.magnet(picker, p, self.edgeZone) or target.followed
    end
    local d = panel.toCorner(picker, pos)
    return d ~= nil and d > self.cornerSnap
  end

  -- Counts a shared edge only once the cursor has stayed for seamDelay. The timer
  -- runs from the first event there, and leaving the edge cancels it.
  function obj:_holdSeam(target, p)
    target.seamPoint = p
    if not self.seamTimer then self.seamTimer = hs.timer.doAfter(self.seamDelay, self.onSeamDwell) end
  end

  function obj:_releaseSeam()
    if self.seamTimer then self.seamTimer:stop() end
    self.seamTimer = nil
  end

  function obj:_seamDwell()
    self.seamTimer = nil
    local target = self.target
    if not target or not target.seamPoint then return end
    target.seamReady = true
    if self:_resolve(target, target.seamPoint) then self:_zone() end
  end
end
