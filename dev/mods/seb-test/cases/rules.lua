-- rules.lua: project rules and controls.
--   uncharted: charted_only is on by default (headless runs chart nothing)
--   area:      growth stays inside the given rectangle
--   pause:     a paused project stamps nothing until resumed
--   stop:      a stopped project never grows

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "rules" }

local REGION = 9
local E = defines.direction.east
local CELL = { { name = "medium-electric-pole", position = { x = 0.5, y = 0.5 } }, { name = "small-lamp", position = { x = 1.5, y = 0.5 } } }

function case.setup(surface)
  local o = rig.region(REGION)
  rig.floor(surface, rig.box(o, -60, -60, 60, 60))
  rig.network(surface, rig.offset(o, -25, -25))
  storage.rules = { design = rig.design(CELL, "Rule cell") }
end

local function start(extra)
  local params = { force = rig.FORCE, surface = game.surfaces.nauvis, design = storage.rules.design }
  for k, v in pairs(extra) do params[k] = v end
  local id, reason = rig.call("start_project", params)
  check.truthy("rules start", id, reason)
  return id
end

function case.start(surface)
  local o, r = rig.region(REGION), storage.rules
  r.uncharted = start({ position = rig.offset(o, 0, 0) })
  r.area = start({ area = rig.box(o, 0, 10, 9, 12), charted_only = false })
  r.paused = start({ position = rig.offset(o, 0, 20), directions = { E }, max_instances = 3, charted_only = false })
  rig.call("pause_project", r.paused)
  r.stopped = start({ position = rig.offset(o, 0, 30), directions = { E }, max_instances = 3, charted_only = false })
  rig.call("stop_project", r.stopped)
end

local function mid(surface)
  local r = storage.rules
  local u = rig.call("get_project", r.uncharted)
  check.eq("rules uncharted closes", u and u.closed.uncharted, 1)
  check.eq("rules uncharted stamps nothing", u and u.count, 0)
  local p = rig.call("get_project", r.paused)
  check.eq("rules paused stamps nothing", p and p.count, 0)
  check.eq("rules paused state", p and p.state, "paused")
  check.truthy("rules resume", rig.call("resume_project", r.paused))
  local s = rig.call("get_project", r.stopped)
  check.eq("rules stopped stamps nothing", s and s.count, 0)
  check.eq("rules stopped state", s and s.state, "stopped")
end

local function late(surface)
  local r = storage.rules
  local a = rig.call("get_project", r.area)
  -- The cell is 2 x 1; the area is 9 x 2: four columns by two rows fit.
  check.eq("rules area count", a and a.count, 8)
  check.truthy("rules area closes at its edge", a and (a.closed["outside-area"] or 0) > 0, check.show(a and a.closed))
  local p = rig.call("get_project", r.paused)
  check.eq("rules resumed project finishes", p and p.state, "finished")
  check.eq("rules resumed project count", p and p.count, 3)
end

case.checks = { [600] = mid, [2400] = late }

return case
