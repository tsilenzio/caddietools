-- Allocation and time per action for Core, under standalone Lua with the stub.
-- Run: lua test/bench_core_alloc.lua
package.path = "./test/?.lua;" .. package.path
local stub = require("stub_hs")
stub.install(".")
local Core = stub.loadSpoon("CaddieCore")

local N = 100000

local function spoonWith(layers, subscribers)
  local s = Core.component({ name = "Bench" .. layers .. "_" .. subscribers })
  s:action("act", { snapshot = function(ctx, result) return { status = result.status } end })
  for i = 1, layers do
    if i % 2 == 1 then
      s:use("act", function(ctx) ctx.proposed.n = (ctx.proposed.n or 0) + 1 end, { kind = "transform", owner = "T" .. i })
    else
      s:use("act", function() end, { kind = "observer", owner = "O" .. i })
    end
  end
  for i = 1, subscribers do s:on("*", function() end, "S" .. i) end
  return s
end

local function perform() return nil end
local function prepare(ctx) ctx.proposed.target = 1 end

local function measure(label, s)
  local input = {}
  for _ = 1, 1000 do s:run("act", input, perform, prepare) end
  collectgarbage("collect")
  collectgarbage("stop")
  local kb0 = collectgarbage("count")
  for _ = 1, N do s:run("act", input, perform, prepare) end
  local bytes = (collectgarbage("count") - kb0) * 1024 / N
  collectgarbage("restart")
  collectgarbage("collect")
  local t0 = os.clock()
  for _ = 1, N do s:run("act", input, perform, prepare) end
  local us = (os.clock() - t0) / N * 1e6
  print(string.format("%-26s %7.3f us  %6.0f B/call", label, us, bytes))
end

print("CaddieCore: " .. package.searchpath("CaddieCore", package.path))
measure("0 middleware", spoonWith(0, 0))
measure("1 middleware", spoonWith(1, 0))
measure("3 middleware", spoonWith(3, 0))
measure("10 middleware", spoonWith(10, 0))
measure("3 middleware + 1 sub", spoonWith(3, 1))
measure("4 middleware + 4 subs", spoonWith(4, 4))
