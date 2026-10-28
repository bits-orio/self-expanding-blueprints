-- S1 placement spike: wiring only. Each cases/qN.lua logs its own verdicts.
local fmt = require("lib.fmt")
local rig = require("lib.rig")
local events = require("lib.events")

local q1 = require("cases.q1")
local q7 = require("cases.q7")
local q8 = require("cases.q8")

local SUITES = {
  q1,
  require("cases.q2"),
  require("cases.q3"),
  require("cases.q4"),
  require("cases.q5"),
  require("cases.q6"),
  q7,
  q8,
}

events.register()

local function run_safe(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then fmt.out(name, "ERROR", (tostring(err):gsub("\n", " | "))) end
end

script.on_init(function()
  storage.sig = {}
  storage.exports = {}
  run_safe("RIG", rig.init)
  for _, suite in ipairs(SUITES) do run_safe(suite.id, suite.run) end
end)

-- Benchmark-time steps (events that need ticks to arrive).
local TICK_STEPS = {
  [5] = function() q7.tick_start() end,
  [12] = function() q7.tick_report() end,
  [15] = function() q7.tick_control() end,
  [20] = function() q1.fog_after_chart() end,
  [25] = function() q8.tick() end,
}

script.on_nth_tick(1, function(e)
  local step = TICK_STEPS[e.tick]
  if step then run_safe("TICK" .. e.tick, step) end
end)
