-- placement.lua: where stamps land (spike S1 kept as a regression test).
-- A design with asymmetric bounds and an entry arrow is stamped in all four
-- directions: the entry must land exactly on the requested point, every
-- entity at its offset from the entry turned by the build direction, and the
-- reported footprint must be the union of the ghosts' tiles. A design
-- without an entry is checked for footprint consistency only.

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "placement" }

local REGION = 0
local D = defines.direction

-- Entry at (0.5, 1.5) facing east; assembler and pole relative to it.
local WITH_ENTRY = {
  { name = "assembling-machine-1", position = { x = 1.5, y = 1.5 } },
  { name = "small-electric-pole", position = { x = 4.5, y = 0.5 } },
  { name = "seb-entry", position = { x = 0.5, y = 1.5 }, direction = D.east },
}
local OFFSETS = { ["assembling-machine-1"] = { x = 1, y = 0 }, ["small-electric-pole"] = { x = 4, y = -1 } }

local function turn(v, d)
  if d == D.east then return { x = -v.y, y = v.x } end
  if d == D.south then return { x = -v.x, y = -v.y } end
  if d == D.west then return { x = v.y, y = -v.x } end
  return { x = v.x, y = v.y }
end

local function ghosts_of(surface, footprint)
  return surface.find_entities_filtered {
    area = { { footprint.left, footprint.top }, { footprint.right, footprint.bottom } }, type = "entity-ghost",
  }
end

local function stamp_and_check(surface, design, at, d, label)
  local id, reason = rig.call("stamp", { force = rig.FORCE, surface = surface, design = design, position = at, direction = d })
  check.truthy(label .. " stamped", id, reason)
  if not id then return end
  local inst = rig.call("get_instance", id)
  local ghosts = ghosts_of(surface, inst.footprint)
  check.same(label .. " footprint is the ghosts' tiles", inst.footprint, rig.tiles_of(ghosts))
  return ghosts
end

local function entry_case(surface, design, at, d)
  local label = "placement entry dir " .. d
  local ghosts = stamp_and_check(surface, design, at, d, label)
  if not ghosts then return end
  check.eq(label .. " ghost count", #ghosts, 2)
  for _, g in pairs(ghosts) do
    local want = turn(OFFSETS[g.ghost_name], d)
    check.same(label .. " " .. g.ghost_name .. " position", g.position, { x = at.x + want.x, y = at.y + want.y })
  end
end

function case.setup(surface)
  local o = rig.region(REGION)
  rig.floor(surface, rig.box(o, -10, -10, 130, 40))
  local with_entry = rig.design(WITH_ENTRY, "Placement entry")
  local plain = rig.design({ WITH_ENTRY[1], WITH_ENTRY[2] }, "Placement plain")
  for i, d in ipairs({ D.north, D.east, D.south, D.west }) do
    entry_case(surface, with_entry, rig.offset(o, i * 25 + 0.5, 10.5), d)
    stamp_and_check(surface, plain, rig.offset(o, i * 25, 30), d, "placement plain dir " .. d)
  end
end

return case
