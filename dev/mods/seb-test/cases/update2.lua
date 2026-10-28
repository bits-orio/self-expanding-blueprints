-- update2.lua: updates in place, the edge cases the second review found.
--   mid-build:  updating a copy that is half built (its lamp can never be
--               delivered) to a version without the lamp lets its project
--               go on and finish
--   water:      a new version with a part over water is refused whole; the
--               copy keeps its version and its parts
--   tiles:      a new version that changes the floor finishes complete
--   robots:     a robot flying over a copy does not refuse its update

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "update2" }

local REGION, WATER_REGION = 51, 52
local D = defines.direction

local function floor(tile)
  local tiles = {}
  for x = 0, 2 do
    for y = 0, 2 do tiles[#tiles + 1] = { name = tile, position = { x = x, y = y } } end
  end
  return tiles
end

local LAMP = { name = "small-lamp", position = { x = 3.5, y = 0.5 } }

function case.setup(surface)
  local o = rig.region(REGION)
  rig.floor(surface, rig.box(o, -60, -60, 60, 60))
  -- No lamps in this network: a lamp ghost here is never built.
  rig.network(surface, rig.offset(o, -25, -25), { { "solar-panel", 50 }, { "concrete", 100 }, { "stone-brick", 100 } })
  local w = rig.site(surface, WATER_REGION)
  rig.water(surface, rig.box(w, 3, -5, 12, 12))
  storage.update2 = {
    cell = rig.design({ rig.panel(1.5, 1.5), LAMP }, "U2 cell"),
    floored = rig.design({ rig.panel(1.5, 1.5) }, "U2 floor", { tiles = floor("stone-path") }),
    shore = rig.design({ rig.panel(1.5, 1.5) }, "U2 shore"),
  }
end

function case.start(surface)
  local u, o = storage.update2, rig.region(REGION)
  u.project = rig.call("start_project", {
    force = rig.FORCE, surface = surface, design = u.cell, charted_only = false, max_instances = 2, materials = false,
    area = rig.box(o, 0, 0, 12, 3), directions = { D.east },
  })
  u.floor_copy = rig.call("stamp", { force = rig.FORCE, surface = surface, design = u.floored, position = rig.offset(o, 0.5, 10.5) })
  u.shore_copy = rig.call("stamp", { force = rig.FORCE, surface = surface, design = u.shore, position = rig.offset(rig.region(WATER_REGION), 0.5, 0.5) })
end

-- The first copy has its panel and waits for a lamp that never comes; its
-- new version has no lamp.
local function mid_build()
  local u = storage.update2
  local p = rig.call("get_project", u.project)
  check.eq("update2 first copy still building", p and p.building, 1)
  rig.call("register_design", rig.FORCE, rig.blueprint({ rig.panel(1.5, 1.5) }, { label = "U2 cell" }))
  local done, refused = rig.call("update_project", u.project)
  check.eq("update2 half-built copy updated", done, 1, refused)
end

local function after_build(surface)
  local u, o = storage.update2, rig.region(REGION)
  -- Concrete instead of stone path.
  rig.call("register_design", rig.FORCE, rig.blueprint({ rig.panel(1.5, 1.5) }, { label = "U2 floor", tiles = floor("concrete") }))
  -- A robot over the floored copy does not count as a building.
  local inst = rig.call("get_instance", u.floor_copy)
  local fp = inst.footprint
  surface.create_entity { name = "construction-robot", position = { fp.left + 1, fp.top + 1 }, force = rig.FORCE }
  local ok, why = rig.call("update_instance", u.floor_copy)
  check.eq("update2 robot overhead does not refuse", ok, true, why)
  -- A part over the lake refuses the whole update.
  rig.call("register_design", rig.FORCE, rig.blueprint({ rig.panel(1.5, 1.5), rig.panel(4.5, 1.5) }, { label = "U2 shore" }))
  local refused, because = rig.call("update_instance", u.shore_copy)
  check.eq("update2 water refuses the update", refused, false)
  check.eq("update2 water reason", because, "water")
  local shore = rig.call("get_instance", u.shore_copy)
  check.eq("update2 refused copy keeps its version", shore and shore.version, 1)
  check.eq("update2 refused copy keeps its parts", shore and shore.entity_count, 1)
end

local function settled(surface)
  local u = storage.update2
  local p = rig.call("get_project", u.project)
  check.eq("update2 project updated mid-build finishes", p and p.state, "finished")
  check.eq("update2 project grew its copies", p and p.count, 2)
  local floored = rig.call("get_instance", u.floor_copy)
  check.eq("update2 floor change finishes complete", floored and floored.state, "complete")
  check.eq("update2 floor change is version 2", floored and floored.version, 2)
end

case.checks = { [900] = mid_build, [960] = after_build, [4200] = settled }

return case
