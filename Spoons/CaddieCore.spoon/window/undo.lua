-- Per-window stacks of the frames windows had before each placement, capped at the
-- undoDepth setting

local M = {}

local Undo = {}
Undo.__index = Undo

function M.new(settings)
  return setmetatable({ settings = settings, stacks = {} }, Undo)
end

function Undo:record(windowID, previousFrame)
  if windowID == nil or not previousFrame then return end
  local stack = self.stacks[windowID]
  if not stack then
    stack = {}
    self.stacks[windowID] = stack
  end
  table.insert(stack, { x = previousFrame.x, y = previousFrame.y, w = previousFrame.w, h = previousFrame.h })
  local depth = self.settings.undoDepth or 20
  while #stack > depth do table.remove(stack, 1) end
end

function Undo:peek(windowID)
  local stack = windowID ~= nil and self.stacks[windowID]
  return stack and stack[#stack] or nil
end

function Undo:pop(windowID)
  local stack = windowID ~= nil and self.stacks[windowID]
  if not stack then return nil end
  local frame = table.remove(stack)
  if #stack == 0 then self.stacks[windowID] = nil end
  return frame
end

function Undo:depth(windowID)
  local stack = self.stacks[windowID]
  return stack and #stack or 0
end

return M
