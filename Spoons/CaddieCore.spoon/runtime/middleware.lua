-- Middleware kinds and chain compilation. A chain is compiled when a layer is added
-- or removed, never per call.

local part = ...
local recordError = part("runtime/context").recordError

local M = {}

-- A guard returns false (and an optional reason) to veto, anything else to pass
local function wrapGuard(fn)
  return function(ctx, nextFn)
    local verdict, reason = fn(ctx)
    if verdict == false then return { status = "vetoed", reason = reason } end
    return nextFn()
  end
end

-- A transform edits ctx.proposed and never decides whether the action runs
local function wrapTransform(fn)
  return function(ctx, nextFn)
    fn(ctx)
    return nextFn()
  end
end

-- An observer always lets the action run, then sees the result
local function wrapObserver(fn)
  return function(ctx, nextFn)
    local result = nextFn()
    fn(ctx, result)
    return result
  end
end

M.WRAPPERS = {
  guard = wrapGuard,
  transform = wrapTransform,
  observer = wrapObserver,
  wrapper = function(fn) return fn end,
}

local traceback = debug.traceback

function M.terminal(ctx)
  local ok, res = xpcall(ctx._perform, traceback, ctx)
  if not ok then return { status = "failed", error = res } end
  return res or { status = "completed" }
end

-- Builds one stage per layer, once. Per-run state lives in upvalues that are saved
-- and restored around each call, so a nested run of the same action stays correct
-- without allocating a closure per layer per call. next() is only valid while the
-- layer is running, which matches the synchronous dispatch.
local function stageFor(layer, inner)
  local fn = layer.fn
  local current, called, downstream

  local function nextFn()
    -- A second call returns the first outcome, so the action never runs twice
    if not called then
      called = true
      downstream = inner(current)
    end
    return downstream
  end

  return function(ctx)
    local savedCurrent, savedCalled, savedDownstream = current, called, downstream
    current, called, downstream = ctx, false, nil
    local ok, res = xpcall(fn, traceback, ctx, nextFn)
    local wasCalled, down = called, downstream
    current, called, downstream = savedCurrent, savedCalled, savedDownstream

    if not ok then
      print(string.format("Core: middleware %s.%s (%s) failed: %s", layer.owner, layer.name, layer.kind, res))
      recordError(ctx, layer.owner, res)
      -- Before next(): skip the broken layer. After it: keep the outcome that already happened.
      if wasCalled then return down end
      return inner(ctx)
    end
    if not wasCalled then
      res = res or {}
      if res.status == nil or res.status == "vetoed" then
        res.status = "vetoed"
        res.by = res.by or layer.owner
      end
      return res
    end
    return res or down
  end
end

function M.compile(chain)
  local stage = M.terminal
  for i = #chain, 1, -1 do stage = stageFor(chain[i], stage) end
  return stage
end

return M
