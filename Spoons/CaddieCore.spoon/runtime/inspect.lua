-- A text dump of every component: its middleware chains, its listeners, and what
-- its scope holds

local part = ...
local components = part("runtime/component").components

return function()
  local lines = {}
  local names = {}
  for name in pairs(components) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    local c = components[name]
    lines[#lines + 1] = name
    for action in pairs(c._actions) do
      lines[#lines + 1] = "  " .. c:stack(action):gsub("\n", "\n  ")
    end
    for event, list in pairs(c._listeners) do
      if #list == 0 then goto continue end
      local owners = {}
      for i, e in ipairs(list) do owners[i] = e.owner end
      lines[#lines + 1] = string.format("  on %s: %s", event, table.concat(owners, ", "))
      ::continue::
    end
    if c.scope then
      lines[#lines + 1] = "  holds: " .. table.concat(c.scope:list(), ", ")
    end
  end
  return table.concat(lines, "\n")
end
