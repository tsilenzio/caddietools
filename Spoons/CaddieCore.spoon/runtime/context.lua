-- The per-run context every action and middleware layer receives

local M = {}

local Context = {}
Context.__index = Context

function M.new(spoonName, action, input, perform)
  return setmetatable({
    spoon = spoonName, action = action, input = input or {},
    proposed = {}, memo = {}, _perform = perform,
  }, Context)
end

-- Caches nil and false too, which a `memo[key] == nil` check would recompute
function Context:get(key, compute)
  local computed = self.computed
  if computed then
    if computed[key] then return self.memo[key] end
  else
    computed = {}
    self.computed = computed
  end
  local value = compute(self)
  self.memo[key] = value
  computed[key] = true
  return value
end

function M.recordError(ctx, owner, err)
  local errors = ctx.errors
  if not errors then
    errors = {}
    ctx.errors = errors
  end
  errors[#errors + 1] = { by = owner, error = err }
end

return M
