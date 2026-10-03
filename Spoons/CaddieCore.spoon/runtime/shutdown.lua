-- hs.shutdownCallback is a single slot, so Core owns it and fans out. Installed when
-- this file loads, chaining onto whatever callback was set before.

local M = {}

local handlers = {}

function M.add(fn)
  table.insert(handlers, fn)
  return function()
    for i, f in ipairs(handlers) do
      if f == fn then table.remove(handlers, i) return end
    end
  end
end

local previous = hs.shutdownCallback
hs.shutdownCallback = function()
  for i = #handlers, 1, -1 do pcall(handlers[i]) end
  if previous then pcall(previous) end
end

return M
