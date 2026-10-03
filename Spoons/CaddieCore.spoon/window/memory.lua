-- Each window's natural frame, the one it had before any placement, so a restore
-- can return it there. Behavior and edge cases: docs/window-memory.md.
--
-- Each window gets two records: `original`, its natural frame and the frame of the
-- screen it was on, and `applied`, the frame last placed and what kind of placement
-- it was. An entry is trusted only while the window still sits at `applied`, so
-- nothing stale is ever applied. An untrusted entry is kept dormant rather than
-- deleted, because macOS can return a window to exactly that frame after a display
-- change. There is no watcher or timer, and no window is moved except by the action
-- that asked for it.

local part = ...
local geometry = part("window/geometry")

local M = {}

local SETTINGS_KEY = "WindowState.memory"

local function rect(r)
  if not r then return nil end
  return { x = r.x, y = r.y, w = r.w, h = r.h }
end

local function within(a, b, slack)
  return math.abs(a.x - b.x) <= slack and math.abs(a.y - b.y) <= slack
    and math.abs(a.w - b.w) <= slack and math.abs(a.h - b.h) <= slack
end

local function round(v)
  return math.floor(v + 0.5)
end

-- The screen frame a window frame sits on, by largest overlap
local function screenFrameOf(frame)
  local entries = geometry.describeScreens(hs.screen.allScreens())
  local here = #entries > 0 and geometry.screenFor(frame, entries)
  return here and rect(here.frame) or nil
end

-- True for a frame that looks placed rather than sized by hand, so it is never
-- recorded as natural. The slack is the tiler's own, 20 pt per edge.
local function looksTiled(frame, sf)
  return geometry.near(frame, sf) or geometry.positionOf(frame, sf) ~= nil
end

-- One axis of a restore onto another screen. The size stays natural when it fits,
-- otherwise it keeps its fraction of the original screen. The position keeps its
-- fraction of the free space, the screen length minus the window length, so a
-- window 40 px from an edge on a large screen stays close to that edge on a small
-- one instead of being scaled past it. Worked example in docs/window-memory.md.
local function mapAxis(pos, size, fromStart, fromLen, toStart, toLen)
  local newSize = size
  if size > toLen then newSize = round(size / fromLen * toLen) end
  newSize = math.min(newSize, toLen)
  local free = fromLen - size
  local fraction = free > 0 and (pos - fromStart) / free or 0
  fraction = math.max(0, math.min(1, fraction))
  return round(toStart + fraction * (toLen - newSize)), newSize
end

function M.restoreFrame(original, toScreen)
  local f, from = original.frame, original.screen
  if not from or within(from, toScreen, 1) then return rect(f) end
  local x, w = mapAxis(f.x, f.w, from.x, from.w, toScreen.x, toScreen.w)
  local y, h = mapAxis(f.y, f.h, from.y, from.h, toScreen.y, toScreen.h)
  return { x = x, y = y, w = w, h = h }
end

local Memory = {}
Memory.__index = Memory

-- `settings` is read live, so a changed trustSlack or maxEntries applies at once
function M.new(settings)
  return setmetatable({ settings = settings, entries = {} }, Memory)
end

-- The entry for a window, if the window is still where a placement last put it
function Memory:trusted(windowID, current)
  local e = windowID and self.entries[windowID]
  if e and current and within(current, e.applied.frame, self.settings.trustSlack) then return e end
  return nil
end

-- Called after every completed placement. A trusted entry keeps its natural frame
-- through any chain of placements. Otherwise the frame the window had before this
-- one becomes natural, unless it looks tiled itself.
function Memory:placed(windowID, before, after, kind)
  if windowID == nil or not before or not after then return end
  local e = self:trusted(windowID, before)
  if not e then
    local sf = screenFrameOf(before)
    local natural = nil
    if sf and not looksTiled(before, sf) then natural = { frame = rect(before), screen = sf } end
    e = { original = natural }
    self.entries[windowID] = e
  end
  e.applied = { frame = rect(after), kind = kind }
  self:save()
end

function Memory:forget(windowID)
  if windowID ~= nil and self.entries[windowID] then
    self.entries[windowID] = nil
    self:save()
  end
end

-- Window IDs become string keys, since a settings plist only has string keys
function Memory:save()
  local out = {}
  for id, e in pairs(self.entries) do out[tostring(id)] = e end
  hs.settings.set(SETTINGS_KEY, out)
end

-- Entries for windows that no longer exist are dropped, and the rest capped
function Memory:load()
  local stored = hs.settings.get(SETTINGS_KEY)
  if type(stored) ~= "table" then return end
  local alive = {}
  for _, info in ipairs(hs.window.list(true) or {}) do
    if info.kCGWindowNumber then alive[info.kCGWindowNumber] = true end
  end
  local kept = 0
  for key, e in pairs(stored) do
    local id = tonumber(key)
    if id and alive[id] and type(e) == "table" and e.applied and kept < self.settings.maxEntries then
      self.entries[id] = e
      kept = kept + 1
    end
  end
  self:save()
end

return M
