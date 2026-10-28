-- gates.lua: gates hold growth without closing sockets.
--   materials: no solar panels in the network -> the project waits; supply
--              them and it carries on
--   capacity:  max_building = 1 -> never more than one instance in flight

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "gates" }

local REGION = 8
local CELL = { { name = "solar-panel", position = { x = 1.5, y = 1.5 } } }
local POLE_CELL = { { name = "medium-electric-pole", position = { x = 0.5, y = 0.5 } } }

function case.setup(surface)
  local o = rig.region(REGION)
  rig.floor(surface, rig.box(o, -60, -60, 60, 60))
  local chest = rig.network(surface, rig.offset(o, -25, -25), { { "medium-electric-pole", 50 } })
  storage.gates = {
    chest = chest,
    design = rig.design(CELL, "Gate cell"),
    poles = rig.design(POLE_CELL, "Gate pole"),
    peak = 0,
  }
end

function case.start(surface)
  local g = storage.gates
  local o = rig.region(REGION)
  g.waiting = rig.call("start_project", {
    force = rig.FORCE, surface = surface, design = g.design, position = rig.offset(o, 0, 0),
    max_instances = 2, directions = { defines.direction.east }, charted_only = false,
  })
  g.capped = rig.call("start_project", {
    force = rig.FORCE, surface = surface, design = g.poles, position = rig.offset(o, 0, 20),
    max_instances = 6, directions = { defines.direction.east }, max_building = 1, charted_only = false,
  })
  check.truthy("gates projects start", g.waiting and g.capped)
end

local function sample()
  local g = storage.gates
  local p = rig.call("get_project", g.capped)
  if p and p.building > g.peak then g.peak = p.building end
end

local function while_starved(surface)
  sample()
  local p = rig.call("get_project", storage.gates.waiting)
  check.eq("gates starved project stamps nothing", p and p.count, 0)
  check.eq("gates starved project waits for materials", p and p.gate, "missing-materials")
  check.eq("gates starved project is still growing", p and p.state, "growing")
  storage.gates.chest.insert { name = "solar-panel", count = 10 }
end

local function after_supply(surface)
  sample()
  local g = storage.gates
  local p = rig.call("get_project", g.waiting)
  check.eq("gates supplied project carries on", p and p.count, 2)
  check.eq("gates supplied project finishes", p and p.state, "finished")
  local c = rig.call("get_project", g.capped)
  check.eq("gates capped project finishes", c and c.state, "finished")
  check.eq("gates capped project count", c and c.count, 6)
  check.truthy("gates never more than one in flight", g.peak <= 1, "peak " .. g.peak)
end

case.checks = {
  [240] = sample, [420] = sample, [600] = while_starved, [780] = sample, [960] = sample,
  [1200] = sample, [1500] = sample, [2400] = after_supply,
}

return case
