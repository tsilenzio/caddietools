-- The component mixin: actions, middleware, events, and runs

local part = ...
local metrics = part("runtime/metrics")
local newContext = part("runtime/context").new
local middleware = part("runtime/middleware")
local WRAPPERS, terminal, compile = middleware.WRAPPERS, middleware.terminal, middleware.compile

local M = {}

-- name -> component, for the inspector
M.components = {}

local traceback = debug.traceback

local Component = {}

-- Declares an action, its doc line, and how to build its event payload
function Component:action(name, spec)
  self._actions[name] = spec or {}
end

function Component:use(action, fn, opts)
  opts = opts or {}
  local kind = opts.kind or "wrapper"
  assert(WRAPPERS[kind], "unknown middleware kind: " .. tostring(kind))
  if not self._actions[action] then
    print(string.format("Core: %s has no declared action %q", self.name, action))
  end
  local layer = {
    fn = WRAPPERS[kind](fn), kind = kind,
    owner = opts.owner or "?", name = opts.name or "?",
  }
  local chain = self._chains[action] or {}
  self._chains[action] = chain
  table.insert(chain, layer)
  self._compiled[action] = compile(chain)
  return function()
    for i, l in ipairs(chain) do
      if l == layer then
        table.remove(chain, i)
        self._compiled[action] = compile(chain)
        return
      end
    end
  end
end

function Component:on(event, fn, owner)
  local list = self._listeners[event] or {}
  self._listeners[event] = list
  local entry = { fn = fn, owner = owner or "?" }
  table.insert(list, entry)
  return function()
    for i, e in ipairs(list) do
      if e == entry then table.remove(list, i) return end
    end
  end
end

local function deliver(list, eventName, payload)
  if not list then return end
  for _, entry in ipairs(list) do
    local ok, err = pcall(entry.fn, payload, eventName)
    if not ok then print(string.format("Core: subscriber %s on %s failed: %s", entry.owner, eventName, err)) end
  end
end

function Component:emit(eventName, buildPayload)
  local exact, any = self._listeners[eventName], self._listeners["*"]
  -- Lists stay behind empty after unsubscribing, so check length, not existence
  if (not exact or #exact == 0) and (not any or #any == 0) then return end
  local payload = buildPayload()
  deliver(exact, eventName, payload)
  deliver(any, eventName, payload)
end

local function defaultSnapshot(ctx, result)
  local payload = { spoon = ctx.spoon, action = ctx.action, status = result.status,
    reason = result.reason, by = result.by }
  for k, v in pairs(result) do
    if payload[k] == nil and type(v) ~= "table" and type(v) ~= "userdata" and type(v) ~= "function" then
      payload[k] = v
    end
  end
  return payload
end

-- Metric and event names are built once per action and status
local function namesFor(self, action)
  local names = self._names[action]
  if not names then
    names = { metric = self.name .. "." .. action, events = {} }
    self._names[action] = names
  end
  return names
end

local function eventName(names, action, status)
  local e = names.events[status]
  if not e then
    e = action .. "." .. status
    names.events[status] = e
  end
  return e
end

local function hasListeners(list)
  return list ~= nil and #list > 0
end

-- Runs one action through its chain. `prepare(ctx)`, if given, fills ctx.proposed
-- before middleware sees it, and may return a result to end the action early.
-- `perform(ctx)` does the work and returns a result table, or nil for a plain completion.
function Component:run(action, input, perform, prepare)
  local names = namesFor(self, action)
  local token = metrics.begin(names.metric)
  local ctx = newContext(self.name, action, input, perform)

  local result
  if prepare then
    local ok, early = xpcall(prepare, traceback, ctx)
    if not ok then
      result = { status = "failed", error = early }
    elseif early then
      result = early
    end
  end
  if not result then
    result = (self._compiled[action] or terminal)(ctx)
  end
  result.action = action
  ctx.result = result

  local name = eventName(names, action, result.status)
  local exact, any = self._listeners[name], self._listeners["*"]
  if hasListeners(exact) or hasListeners(any) then
    local spec = self._actions[action]
    local payload = (spec and spec.snapshot or defaultSnapshot)(ctx, result)
    deliver(exact, name, payload)
    deliver(any, name, payload)
  end
  -- Timed through delivery, so the figure includes the subscribers an action triggers
  metrics.finish(token, result.status)
  return result, ctx
end

function Component:stack(action)
  local lines = { self.name .. "." .. action }
  for i, l in ipairs(self._chains[action] or {}) do
    lines[#lines + 1] = string.format("  %d. %s.%s  %s", i, l.owner, l.name, l.kind)
  end
  return table.concat(lines, "\n")
end

-- Adds the component methods to a Spoon table and registers it for inspection
function M.mixin(spoonObj)
  spoonObj._actions = spoonObj._actions or {}
  spoonObj._chains = spoonObj._chains or {}
  spoonObj._listeners = spoonObj._listeners or {}
  spoonObj._compiled = spoonObj._compiled or {}
  spoonObj._names = spoonObj._names or {}
  for k, fn in pairs(Component) do spoonObj[k] = fn end
  M.components[spoonObj.name] = spoonObj
  return spoonObj
end

return M
