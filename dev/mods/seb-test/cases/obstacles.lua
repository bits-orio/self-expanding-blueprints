-- obstacles.lua: stamps are all or nothing and name what stopped them.
-- Water, cliffs and other buildings refuse a stamp with that reason and a
-- map position; trees and rocks do not (forced mode marks them for
-- deconstruction); another instance refuses it as joined.

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "obstacles" }

local REGION = 1

local DESIGN = {
  { name = "assembling-machine-1", position = { x = 1.5, y = 1.5 } },
  { name = "small-electric-pole", position = { x = 4.5, y = 0.5 } },
  { name = "seb-entry", position = { x = 0.5, y = 1.5 }, direction = defines.direction.east },
}

-- With the entry on `at` (facing north build), the assembler covers
-- at + (-0.5..2.5, -1.5..1.5) and the pole sits at at + (4, -1).
local function assembler_tile(at) return { x = at.x + 1, y = at.y } end

local function stamp(surface, design, at)
  return rig.call("stamp", { force = rig.FORCE, surface = surface, design = design, position = at })
end

local function refused(surface, design, at, want, label)
  local id, reason, where = stamp(surface, design, at)
  check.eq(label .. " refused", id, nil)
  check.eq(label .. " reason", reason, want)
  check.truthy(label .. " names a position", type(where) == "table" and where.x ~= nil, check.show(where))
  check.eq(label .. " leaves no ghosts", rig.ghosts(surface, rig.box(at, -3, -4, 8, 4)), 0)
end

local function allowed(surface, design, at, label)
  local id, reason = stamp(surface, design, at)
  check.truthy(label .. " stamped", id, reason)
  return id
end

local function plain_stamp(surface, design, at)
  return rig.call("stamp", { force = rig.FORCE, surface = surface, design = design, position = at })
end

-- Stamps once on dry ground to learn where the design's first tile lands,
-- then floods that tile 20 tiles further east and stamps there.
local function over_flooded_tile(surface, design, at)
  local id = plain_stamp(surface, design, at)
  local inst = id and rig.call("get_instance", id)
  if not inst then return nil, "first stamp failed" end
  local x, y = inst.footprint.left + 20, inst.footprint.top
  surface.set_tiles({ { name = "water", position = { x, y } } })
  return plain_stamp(surface, design, rig.offset(at, 20, 0))
end

local function terrain_cases(surface, o)
  -- A rail design only translates by even steps: one of two neighbouring
  -- entry targets lands off the rail grid and is refused, not misplaced.
  local rails = rig.design({
    { name = "straight-rail", position = { x = 1, y = 1 } },
    { name = "seb-entry", position = { x = 0.5, y = 0.5 }, direction = defines.direction.east },
  }, "Obstacle rails")
  local a = { plain_stamp(surface, rails, rig.offset(o, 10.5, 30.5)) }
  local b = { plain_stamp(surface, rails, rig.offset(o, 15.5, 30.5)) }
  local refusals = (a[1] and 0 or 1) + (b[1] and 0 or 1)
  check.eq("obstacles rails: one of two targets is off the grid", refusals, 1)
  check.truthy("obstacles rails: the refusal says off-grid", a[2] == "off-grid" or b[2] == "off-grid",
    check.show({ a[2], b[2] }))

  local drill = rig.design({ { name = "electric-mining-drill", position = { x = 1.5, y = 1.5 } } }, "Obstacle drill")
  local id, reason = plain_stamp(surface, drill, rig.offset(o, 30, 30))
  check.eq("obstacles drill without ore refused", id, nil)
  check.eq("obstacles drill reason", reason, "no-resource")

  local paved = rig.design({ { name = "iron-chest", position = { x = 2.5, y = 0.5 } } }, "Obstacle paved", {
    tiles = { { name = "stone-path", position = { x = 0, y = 0 } }, { name = "stone-path", position = { x = 1, y = 0 } },
      { name = "stone-path", position = { x = 0, y = 1 } }, { name = "stone-path", position = { x = 1, y = 1 } } },
  })
  local wet, why = over_flooded_tile(surface, paved, rig.offset(o, 40, 30))
  check.eq("obstacles paving over water refused", wet, nil)
  check.eq("obstacles paving over water reason", why, "water")

  local pier = rig.design({ { name = "iron-chest", position = { x = 0.5, y = 0.5 } } }, "Obstacle pier", {
    tiles = { { name = "landfill", position = { x = 0, y = 0 } } },
  })
  local built, because = over_flooded_tile(surface, pier, rig.offset(o, 80, 30))
  check.truthy("obstacles own landfill lets a chest stand over water", built, because)
end

function case.setup(surface)
  local o = rig.region(REGION)
  rig.floor(surface, rig.box(o, -10, -10, 160, 40))
  local design = rig.design(DESIGN, "Obstacle course")

  local at = rig.offset(o, 10.5, 10.5)
  surface.set_tiles({ { name = "water", position = assembler_tile(at) } })
  refused(surface, design, at, "water", "obstacles water")

  at = rig.offset(o, 30.5, 10.5)
  surface.create_entity { name = "iron-chest", position = assembler_tile(at), force = rig.FORCE }
  refused(surface, design, at, "building", "obstacles building")

  at = rig.offset(o, 50.5, 10.5)
  local cliff = surface.create_entity { name = "cliff", position = assembler_tile(at), cliff_orientation = "west-to-east" }
  if cliff then
    refused(surface, design, at, "cliff", "obstacles cliff")
  else
    check.info("obstacles cliff skipped: no cliff could be created on lab tiles")
  end

  at = rig.offset(o, 70.5, 10.5)
  local tree = surface.create_entity { name = "tree-01", position = assembler_tile(at) }
  allowed(surface, design, at, "obstacles tree")
  check.truthy("obstacles tree marked for deconstruction", tree and tree.valid and tree.to_be_deconstructed())

  at = rig.offset(o, 90.5, 10.5)
  surface.create_entity { name = "huge-rock", position = assembler_tile(at) }
  allowed(surface, design, at, "obstacles rock")

  terrain_cases(surface, o)

  at = rig.offset(o, 110.5, 10.5)
  local first = allowed(surface, design, at, "obstacles first of two")
  local id, reason = stamp(surface, design, rig.offset(at, 2, 0))
  check.eq("obstacles overlapping instance refused", id, nil)
  check.eq("obstacles overlapping instance reason", reason, "joined")
  check.truthy("obstacles first stays", first and rig.call("get_instance", first))
end

return case
