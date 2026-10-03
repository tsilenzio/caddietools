-- WindowState: the one place every window placement goes through, so memory, undo,
-- and the placement rules apply the same way whichever Spoon placed the window.
-- Core.window() creates it on first call and returns that instance after.
--
-- Actions, each a Core action others can guard, transform, or observe:
--   place(win, opts)    opts: kind ("tile", "maximize", "move"), frame, screenFrame,
--                       position, screen, movedScreen, previousFrame, source
--   restore(win, opts)  opts: source, fallback(win, ctx) -> method, frame
--   undo(win)
-- Events are `<action>.<status>`, with payloads carrying `source` so a subscriber
-- can tell a hotkey tile from an edge drop or a green-button maximize.

local part = ...
local component = part("runtime/component")
local target = part("window/target")
local place = part("window/place")
local restore = part("window/restore")
local rules = part("window/rules")

local M = {}

-- Settings, read live by the rules, memory, and undo. A rule is off while its
-- setting is nil or empty.
local DEFAULTS = {
  -- Points between a placed window and its neighbors or the screen's inner edges
  gap = 0,
  -- Bundle IDs whose windows are never placed, restored, or undone
  excluded = nil,
  -- Smallest tile or maximize, { w, h }, below which the action is vetoed
  minSize = nil,
  -- Apps whose tiles shrink to `fraction` of the tile: { fraction, apps = { [id] = true } }
  centerSmall = nil,
  -- Apps whose maximize takes a fraction of the screen: { [id] = { w, h } }
  presets = nil,
  -- Frames remembered per window for undo
  undoDepth = 20,
  -- Frames within this many points of where a placement left a window count as untouched
  trustSlack = 1,
  -- Remembered windows kept across a reload
  maxEntries = 200,
}

local State = {}
State.__index = State

function State:place(win, opts)
  local input = { window = win }
  for k, v in pairs(opts or {}) do input[k] = v end
  return target.complete(self:run("place", input, place.perform, place.prepare))
end

function State:restore(win, opts)
  local input = { window = win }
  for k, v in pairs(opts or {}) do input[k] = v end
  return target.complete(self:run("restore", input, restore.performRestore, self._prepareRestore))
end

function State:undo(win)
  return target.complete(self:run("undo", { window = win, source = "undo" }, self._performUndo, self._prepareUndo))
end

-- The memory entry for a window still sitting where its last placement left it
function State:trusted(windowID, currentFrame)
  return self.memory:trusted(windowID, currentFrame)
end

function M.new()
  local state = setmetatable({ name = "WindowState" }, State)
  for k, v in pairs(DEFAULTS) do state[k] = v end
  component.mixin(state)

  state.memory = part("window/memory").new(state)
  state.undoStack = part("window/undo").new(state)
  state._prepareRestore = restore.prepareRestore(state.memory)
  state._prepareUndo = restore.prepareUndo(state.undoStack)
  state._performUndo = restore.performUndo(state.undoStack)

  state:action("place", { doc = "Put a window at a frame", snapshot = target.snapshot })
  state:action("restore", { doc = "Return a window to its natural frame", snapshot = target.snapshot })
  state:action("undo", { doc = "Return a window to its frame before the last placement", snapshot = target.snapshot })
  rules.install(state)

  state:on("place.completed", function(p)
    state.memory:placed(p.windowID, p.previousFrame, p.finalFrame, p.position or p.kind)
    state.undoStack:record(p.windowID, p.previousFrame)
  end, state.name)
  state:on("restore.completed", function(p)
    state.memory:forget(p.windowID)
    state.undoStack:record(p.windowID, p.previousFrame)
  end, state.name)

  state.memory:load()
  return state
end

return M
