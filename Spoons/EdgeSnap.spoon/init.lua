--- === EdgeSnap ===
---
--- Tiles a window dropped on a screen edge (TKT-047): the left or right edge to that
--- half, the bottom edge to the bottom half, the top edge maximizes, and near a
--- corner to the quarter of that corner. While a dragged window is held there a
--- preview shows where it will go, as macOS does, and the quick select panel, after
--- BetterTouchTool's, offers that edge's placements close to the cursor (panel/).
---
--- The placement runs through Core.window(), WindowState's place action with source
--- "snap", so its rules, memory, and undo treat it as they treat the hotkeys.
--- Behavior, settings, and history: docs/edge-drag.md.

local Core = require("CaddieCore")
local part = Core.part
local panel = part("panel/init")

local obj = {}
obj.__index = obj

obj.name = "EdgeSnap"
obj.version = "0.1.0"

-- The panel's layout, selection, and drawing, for anything that needs to read it
obj.panel = panel

for _, name in ipairs({ "zones", "drag", "resolve", "guard", "display", "drop", "animate", "preview" }) do
  part(name)(obj)
end

-- Points inside a screen's usable area that still count as its edge. The zone runs
-- from there out to the physical edge, so the menu bar and a visible Dock are part
-- of it. Rectangle uses 5 from the physical edge, which puts the top zone inside
-- the menu bar.
obj.edgeZone = 16
-- Points from each corner of a screen's usable frame, along both of its edges, that
-- count as that corner. The same on every edge and screen, whatever its size or
-- neighbors.
obj.cornerZone = 144
-- The corner panel at each edge
obj.edgePicker = true
-- Where two screens meet, each side of the shared edge counts as an edge of the
-- screen the cursor is on. A drag across it shows the preview in passing, and
-- nothing snaps unless the window is released there.
obj.seams = true
-- Seconds the cursor has to stay at a shared edge before it counts, so a drag on to
-- the next screen passes without a flash. 0 counts it at once.
obj.seamDelay = 0
-- Seconds added to the preview's grow and to both fade-ins at a shared edge, so a
-- drag on to the next screen gets the cue at once but a gentler one
obj.seamTween = 0
-- A straight panel more than edgeZone points behind the cursor along its edge is
-- pulled after it, and its drawing eases there like a smooth scroll: each frame it
-- covers the share of the remaining distance this time constant in seconds gives.
-- 0 moves it at once.
obj.pickerFollow = 0.08
-- A straight panel heading for a corner keeps following until its end is this many
-- points from the corner, then is drawn into it and becomes the corner's L
obj.cornerSnap = 288
-- The time constant, in seconds, of that last pull into the corner, half the
-- follow's so the corner draws the panel in harder
obj.cornerPull = 0.04
-- Rectangle's guard against a window drag opening Mission Control, from its
-- SnappingManager filter, where it is off unless missionControlDragging is turned
-- off. With the cursor held at the very top of a screen, an upward jerk of more than
-- guardDistance points is moved 1 pt down, and so is everything there for
-- guardSeconds after. Only a top edge with no screen above, so a drag can still
-- carry on to a screen stacked above.
obj.missionControlGuard = true
obj.guardDistance = 25
obj.guardSeconds = 0.25
-- Preview timing in seconds. Rectangle's FootprintWindow and WindowAnimationCurves.swift
-- give 0.26, 0.18, and 0.12, since Apple publishes none for its own tiling. The grow
-- and fade-in carry 0.05 more, the shared-edge pace the owner tried on every edge.
obj.previewGrow = 0.31
obj.previewFadeIn = 0.23
obj.previewFadeOut = 0.12

-- Lifecycle ---------------------------------------------------------------------

function obj:init()
  Core.component(self)
  return self
end

function obj:start()
  if self.scope then return self end
  self.scope = Core.scope(self.name)
  self.onDown = function() self:_down() end
  self.onDrag = function(e) return self:_onDrag(e) end
  self.onZone = function() self:_zone() end
  self.onSeamDwell = function() self:_seamDwell() end
  self.onFollow = function() self:_follow() end
  self.onAnimTick = function() self:_animTick() end
  self.anims = {}
  self.preview = self:_newPreview()
  self.picker = panel.newCanvas()
  self.scope:add(function()
    for _, key in ipairs({ "downTimer", "zoneTimer", "dropTimer", "seamTimer", "followTimer" }) do
      if self[key] then self[key]:stop() end
      self[key] = nil
    end
    self:_endDrag()
    self:_stopAnim()
    self.preview:delete()
    self.picker:delete()
    self.preview, self.picker = nil, nil
  end, "drag hold, timers, preview, and corner panel")
  self.scope:add(Core.titlebar():subscribe(self.name, function(e) return self:_onClick(e) end), "title-bar clicks")
  return self
end

function obj:stop()
  if self.scope then self.scope:close() end
  self.scope = nil
  return self
end

return obj
