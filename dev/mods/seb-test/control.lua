-- Headless tests for Self-Expanding Blueprints, driven through the remote
-- interface (a test mod runs in its own Lua state). Three phases:
--   on_init      rig + synchronous contract cases
--   START_TICK   growth scenarios start (each in its own region and network)
--   CHECK_TICKS  scenarios verify; the last one prints SEB_TEST DONE
-- The --benchmark phase loads the save, so on_load re-registration of the
-- mod's queue handler is exercised by every growth scenario.

local check = require("lib.check")
local rig = require("lib.rig")

local CASES = {
  require("cases.library"),
  require("cases.placement"),
  require("cases.obstacles"),
  require("cases.tracking"),
  require("cases.fill"),
  require("cases.sockets"),
  require("cases.gates"),
  require("cases.rules"),
  require("cases.events"),
  require("cases.priming"),
  require("cases.remote"),
  require("cases.edges"),
  require("cases.exact"),
  require("cases.frontier"),
  require("cases.compat"),
  require("cases.snapping"),
  require("cases.regressions"),
  require("cases.feedback"),
  require("cases.mining"),
  require("cases.circuit"),
  require("cases.probes"),
  require("cases.plan"),
  require("cases.update"),
  require("cases.options"),
  require("cases.platform"),
  require("cases.update2"),
  require("cases.circuit2"),
  require("cases.clear"),
  require("cases.limits_growth"),
  require("cases.limits_designs"),
  require("cases.limits_builders"),
  require("cases.limits_copies"),
  require("cases.limits_reads"),
  require("cases.fix_checks"),
  require("cases.fix_cliffs"),
  require("cases.fix_charges"),
  require("cases.fix_plans"),
  require("cases.limits_roster"),
  require("cases.fix_builders"),
  require("cases.fix_builders_many"),
  require("cases.fix_designs"),
  require("cases.fix_updates"),
  require("cases.fix_integrate"),
  require("cases.fix_mirror"),
  require("cases.fix_mirror_sockets"),
  require("cases.fix_server"),
  require("cases.water"),
  require("cases.water_floors"),
  require("cases.delete_design"),
  require("cases.creeper"),
  require("cases.creeper_race"),
  require("cases.creeper_one"),
}

local START_TICK = 60
local LAST_TICK = 11400

-- The mod's custom events, resolved per session (ids are never stored) and
-- handed to every case that defines on_event(name, payload).
local EVENT_NAMES = {
  "on_instance_completed", "on_instance_blocked", "on_instance_stalled",
  "on_instance_retired", "on_project_finished", "on_materials_missing",
}

local function subscribe()
  for _, name in ipairs(EVENT_NAMES) do
    local id = remote.call(rig.REMOTE, "get_event_id", name)
    if id then
      script.on_event(id, function(payload)
        for _, case in ipairs(CASES) do
          if case.on_event then case.on_event(name, payload) end
        end
      end)
    end
  end
end

script.on_init(function()
  subscribe()
  local surface = rig.prepare()
  for _, case in ipairs(CASES) do
    if case.setup then check.run(case.name .. ".setup", function() case.setup(surface) end) end
  end
end)

script.on_load(subscribe)

-- Fixed check ticks per case; collected so one on_nth_tick drives them all.
local function due_checks(tick)
  local due = {}
  for _, case in ipairs(CASES) do
    for at, fn in pairs(case.checks or {}) do
      if at == tick then due[#due + 1] = { case = case, fn = fn } end
    end
  end
  return due
end

script.on_nth_tick(60, function(event)
  local tick = event.tick
  if tick == 0 or storage.finished then return end
  local surface = game.surfaces.nauvis
  if tick == START_TICK then
    for _, case in ipairs(CASES) do
      if case.start then check.run(case.name .. ".start", function() case.start(surface) end) end
    end
  end
  for _, item in ipairs(due_checks(tick)) do
    check.run(item.case.name .. ".check@" .. tick, function() item.fn(surface) end)
  end
  if tick >= LAST_TICK then
    storage.finished = true
    check.done()
  end
end)

