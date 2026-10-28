-- retry.lua: blocked sockets are tried again.
--   by hand:   a probe project that finished at the edge of its ore grows
--              on over ore laid later, once retry_project is called
--   by itself: a building in the way that is destroyed (raise_destroy)
--              frees its spot, and the finished project grows on there

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "retry" }

local PROBE_REGION, BUILDING_REGION = 193, 194
local D = defines.direction

local CHEST = { name = "iron-chest", position = { x = 0.5, y = 0.5 } }
local PROBE = {
  name = "seb-probe", position = { x = 0.5, y = 0.5 },
  control_behavior = { sections = { sections = { { index = 1, filters = {
    { index = 1, type = "item", name = "iron-ore", quality = "normal", comparator = "=", count = 1 },
  } } } } },
}

local function ore(surface, o, x)
  surface.create_entity { name = "iron-ore", position = { o.x + x + 0.5, o.y + 0.5 }, amount = 100 }
end

function case.setup(surface)
  local p = rig.site(surface, PROBE_REGION)
  for x = 0, 2 do ore(surface, p, x) end
  local b = rig.site(surface, BUILDING_REGION)
  storage.retry = {
    iron = rig.design({ CHEST, PROBE }, "Retry iron"),
    chest = rig.design({ CHEST }, "Retry chest"),
    furnace = surface.create_entity { name = "stone-furnace", position = { b.x + 3, b.y + 1 }, force = rig.FORCE },
  }
end

local function start(design, region, max)
  local id, reason = rig.call("start_project", {
    force = rig.FORCE, surface = game.surfaces.nauvis, design = design, charted_only = false,
    area = rig.box(rig.region(region), 0, 0, 10, 1), directions = { D.east }, max_instances = max,
  })
  check.truthy("retry project starts", id, reason)
  return id
end

function case.start()
  local s = storage.retry
  s.probe_project = start(s.iron, PROBE_REGION, 6)
  s.building_project = start(s.chest, BUILDING_REGION, 4)
end

-- Both have stopped at their block; ore is laid past the probe's edge (no
-- event says so) and the furnace is destroyed (its event frees the spot).
local function block()
  local s = storage.retry
  local p = rig.call("get_project", s.probe_project)
  check.eq("retry probe project stops at the ore's edge", p and p.count, 3)
  check.eq("retry probe project finished", p and p.status.level, "finished")
  local b = rig.call("get_project", s.building_project)
  check.eq("retry building project stops at the furnace", b and b.count, 2)
  check.eq("retry building project closed on the building", b and b.closed.building, 1)
  local surface = game.surfaces.nauvis
  ore(surface, rig.region(PROBE_REGION), 3)
  check.eq("retry nothing grows before a retry", rig.call("get_project", s.probe_project).count, 3)
  s.furnace.destroy { raise_destroy = true }
  check.eq("retry by hand reopens the probe's socket", rig.call("retry_project", s.probe_project), 1)
end

local function verify()
  local s = storage.retry
  local p = rig.call("get_project", s.probe_project)
  check.eq("retry probe project grows over the new ore", p and p.count, 4)
  check.eq("retry probe project closes at the next edge", p and p.closed.probe, 1)
  check.eq("retry probe project finished again", p and p.status.level, "finished")
  local b = rig.call("get_project", s.building_project)
  check.eq("retry building project grows on once the furnace is gone", b and b.count, 4)
  check.eq("retry building project has no block left", b and (b.closed.building or 0), 0)
  check.eq("retry a stopped project tries nothing", (function()
    rig.call("stop_project", s.building_project)
    return rig.call("retry_project", s.building_project)
  end)(), 0)
end

case.checks = { [1500] = block, [3000] = verify }

return case
