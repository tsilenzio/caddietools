-- Entry point for running this checkout as a whole config. Run it from
-- ~/.hammerspoon/init.lua with
--   dofile("/path/to/this/repo/init.lua")
-- It hands the profile named in ~/.hammerspoon/profile, or `default` when that file
-- is missing, to CaddieTools' use(). A config that only wants some of the Spoons can
-- call use() itself instead, as CaddieTools.spoon/init.lua describes.

local root = debug.getinfo(1, "S").source:match("^@(.*)/init%.lua$")

package.path = root .. "/Spoons/?.spoon/init.lua;" .. package.path

local function profileName()
  local f = io.open(hs.configdir .. "/profile")
  if not f then return "default" end
  local line = f:read("l")
  f:close()
  return line and line:match("^%s*(%S+)") or "default"
end

-- CaddieTools has AutoReload watch this checkout when it lies outside the config
-- directory, so edits here reload too
local M = { root = root, profile = profileName() }
M.spoons = hs.loadSpoon("CaddieTools").use(dofile(root .. "/profiles/" .. M.profile .. ".lua"))

return M
