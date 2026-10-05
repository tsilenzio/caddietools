-- Default profile: which CaddieTools Spoons to use and how, as one table for
-- CaddieTools' use(). init.lua loads it.

return {
  "AutoReload",
  WindowState = {
    config = {
      gap = 1,
      excluded = { ["com.apple.systempreferences"] = true },
      minSize = { w = 400, h = 300 },
      centerSmall = { fraction = 0.8, apps = { ["com.apple.calculator"] = true } },
      presets = { ["com.apple.Terminal"] = { w = 0.6, h = 0.7 } },
    },
  },
  "TileManager",
  "TitleBarTweaks",
  "EdgeSnap",
  "MouseTweaks",
}
