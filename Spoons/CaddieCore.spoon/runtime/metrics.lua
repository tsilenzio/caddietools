-- Action timing. Keeps the last SAMPLES durations per action name, which Core.run
-- records for every action and Core.metrics exposes.

local M = {}

local SAMPLES = 500
local now = hs.timer.absoluteTime

local stats = {}

local function entry(name)
  local s = stats[name]
  if not s then
    s = { count = 0, sumNs = 0, maxNs = 0, samples = {}, next = 1, statuses = {} }
    stats[name] = s
  end
  return s
end

function M.begin(name)
  return { name = name, t0 = now() }
end

function M.finish(token, status)
  M.record(token.name, now() - token.t0, status)
end

function M.record(name, ns, status)
  local s = entry(name)
  s.count = s.count + 1
  s.sumNs = s.sumNs + ns
  if ns > s.maxNs then s.maxNs = ns end
  s.samples[s.next] = ns
  s.next = s.next % SAMPLES + 1
  if status then s.statuses[status] = (s.statuses[status] or 0) + 1 end
end

local function percentile(sorted, p)
  if #sorted == 0 then return 0 end
  local i = math.max(1, math.ceil(#sorted * p))
  return sorted[i]
end

-- Durations are reported in microseconds
function M.snapshot()
  local out = {}
  for name, s in pairs(stats) do
    local sorted = { table.unpack(s.samples) }
    table.sort(sorted)
    out[name] = {
      count = s.count,
      meanUs = s.count > 0 and s.sumNs / s.count / 1e3 or 0,
      medianUs = percentile(sorted, 0.5) / 1e3,
      p95Us = percentile(sorted, 0.95) / 1e3,
      maxUs = s.maxNs / 1e3,
      statuses = s.statuses,
    }
  end
  return out
end

function M.reset()
  stats = {}
end

function M.dump(path)
  local f = assert(io.open(path, "w"))
  f:write(hs.json.encode(M.snapshot(), true))
  f:close()
  return path
end

return M
