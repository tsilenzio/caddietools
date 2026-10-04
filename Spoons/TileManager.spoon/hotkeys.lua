-- The hotkey mapping, added to the Spoon by init.lua. Hotkeys live in their own scope
-- inside the Spoon's, so rebinding while started leaves the Space chord tap alone.

local part = ...
local Core = require("CaddieCore")
local chord = part("chord")

local KEYS = {
  "left", "right", "up", "down", "maximize", "undo",
  "topLeft", "topRight", "bottomLeft", "bottomRight",
  "firstThird", "centerThird", "lastThird",
  "firstTwoThirds", "centerTwoThirds", "lastTwoThirds",
}

local function handlers(obj)
  -- With Space held in the chord an arrow moves to the next screen instead of tiling
  local function arrow(direction)
    return function()
      if chord.held then obj:moveScreen(direction) else obj:tile(direction) end
    end
  end
  local function place(position)
    return function() obj:tile(position) end
  end
  return {
    left = arrow("left"), right = arrow("right"), up = arrow("up"), down = arrow("down"),
    topLeft = place("topLeft"), topRight = place("topRight"),
    bottomLeft = place("bottomLeft"), bottomRight = place("bottomRight"),
    firstThird = place("firstThird"), centerThird = place("centerThird"), lastThird = place("lastThird"),
    firstTwoThirds = place("firstTwoThirds"), centerTwoThirds = place("centerTwoThirds"),
    lastTwoThirds = place("lastTwoThirds"),
    maximize = function() obj:maximize() end,
    undo = function()
      local win = hs.window.focusedWindow()
      if win then Core.window():undo(win) end
    end,
  }
end

return function(obj)
  -- Replaces whatever hotkeys are bound with the current mapping
  function obj:_rebind()
    if self.hotkeys then self.hotkeys:close() end
    local hk = Core.scope(self.name .. " hotkeys")
    local fns = handlers(self)
    for _, key in ipairs(KEYS) do
      local spec = self.mapping and self.mapping[key]
      if spec then hk:hotkey(spec[1], spec[2], fns[key]) end
    end
    self.hotkeys = hk
  end

  function obj:_unbind()
    if self.hotkeys then self.hotkeys:close() end
    self.hotkeys = nil
  end

  -- Hotkeys are created in :start(). Binding while started rebinds immediately.
  function obj:bindHotkeys(mapping)
    self.mapping = mapping
    if self.scope then self:_rebind() end
    return self
  end
end
