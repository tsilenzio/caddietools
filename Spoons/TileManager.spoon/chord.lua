-- Tracks Space held together with Ctrl+Opt+Cmd, so an arrow hotkey can tell the plain
-- chord from the Space chord. Space is not a modifier, so this needs a key tap. Every
-- Space event that belongs to the chord is swallowed, including key repeats and the
-- release, so no space is typed and nothing else sees it.

local M = { held = false }

local SPACE = 49
local KEY_UP = hs.eventtap.event.types.keyUp

-- Tap callback. Returns true to swallow the event.
function M.handle(event)
  if event:getKeyCode() ~= SPACE then return false end
  if event:getType() == KEY_UP then
    if M.held then
      M.held = false
      return true
    end
    return false
  end
  if M.held then return true end
  local flags = event:getFlags()
  if flags.ctrl and flags.alt and flags.cmd then
    M.held = true
    return true
  end
  return false
end

function M.reset()
  M.held = false
end

return M
