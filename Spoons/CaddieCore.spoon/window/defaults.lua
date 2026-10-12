-- WindowState's settings and their defaults, the one place to change them. A config
-- can still override any of them through CaddieTools' use(), as
-- `WindowState = { config = { gap = 4 } }`. A rule is off while its setting is nil
-- or empty.

return {
  -- Points between a placed window and its neighbors or the screen's inner edges
  gap = 1,
  -- Bundle IDs whose windows are never placed, restored, or undone
  excluded = { ["com.apple.systempreferences"] = true },
  -- Smallest tile or maximize, { w, h }, below which the action is vetoed
  minSize = { w = 400, h = 300 },
  -- Apps whose tiles shrink to `fraction` of the tile: { fraction, apps = { [id] = true } }
  centerSmall = { fraction = 0.8, apps = { ["com.apple.calculator"] = true } },
  -- Apps whose maximize takes a fraction of the screen: { [id] = { w, h } }
  presets = { ["com.apple.Terminal"] = { w = 0.6, h = 0.7 } },
  -- Frames remembered per window for undo
  undoDepth = 20,
  -- Frames within this many points of where a placement left a window count as untouched
  trustSlack = 1,
  -- Remembered windows kept across a reload
  maxEntries = 200,
}
