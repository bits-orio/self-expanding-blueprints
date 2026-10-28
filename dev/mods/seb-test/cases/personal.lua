-- personal.lua: a player's personal roboport is a construction network of
-- its own, holding the player's pockets. Standing by a project with more
-- idle robots than the base, it used to decide the materials gate alone
-- ("needs 2, the network can spare 1" while the base held plenty). Roboport
-- networks now decide, summed, and a personal one counts only where none
-- reaches (gates.networks_at).
--   base:   next to a character with idle robots and one underground belt in
--           its pockets, a project of underground pairs grows on the base's
--           stock
--   alone:  where only the personal roboport reaches, the pockets decide

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "personal" }

local BASE_REGION, ALONE_REGION = 190, 191
local D = defines.direction
local PAIR = {
  { name = "underground-belt", position = { x = 0.5, y = 0.5 }, direction = D.east, type = "input" },
  { name = "underground-belt", position = { x = 3.5, y = 0.5 }, direction = D.east, type = "output" },
}

-- A roboport network with fewer robots than the character carries.
local function base(surface, at)
  local function make(name, dx, dy)
    return surface.create_entity { name = name, position = { at.x + dx, at.y + dy }, force = rig.FORCE }
  end
  local eei = make("electric-energy-interface", -4, -4)
  eei.power_production, eei.electric_buffer_size = 1e9, 1e10
  make("medium-electric-pole", -2.5, -2.5)
  make("roboport", 0, 0).insert { name = "construction-robot", count = 5 }
  make("storage-chest", 3.5, -2.5).insert { name = "underground-belt", count = 20 }
end

-- A character in power armour with a personal roboport, 20 robots and one
-- underground belt in its pockets.
local function character(surface, at)
  local c = surface.create_entity { name = "character", position = at, force = rig.FORCE }
  local armor = c.get_inventory(defines.inventory.character_armor)
  armor.insert { name = "power-armor-mk2" }
  armor[1].grid.put { name = "fission-reactor-equipment" }
  armor[1].grid.put { name = "personal-roboport-mk2-equipment" }
  c.insert { name = "construction-robot", count = 20 }
  c.insert { name = "underground-belt", count = 1 }
end

local function start(region)
  local id, reason = rig.call("start_project", {
    force = rig.FORCE, surface = game.surfaces.nauvis, design = storage.personal.pair, charted_only = false,
    position = rig.offset(rig.region(region), 0.5, 0.5), directions = { D.east }, max_instances = 3,
  })
  check.truthy("personal project starts in region " .. region, id, reason)
  return id
end

function case.setup(surface)
  for _, region in ipairs({ BASE_REGION, ALONE_REGION }) do
    local o = rig.region(region)
    rig.floor(surface, rig.box(o, -60, -60, 60, 60))
    character(surface, rig.offset(o, 6, 4))
  end
  base(surface, rig.offset(rig.region(BASE_REGION), -20, -10))
  storage.personal = { pair = rig.design(PAIR, "Personal pair") }
  check.truthy("personal design registered", storage.personal.pair)
end

function case.start()
  local p = storage.personal
  p.base = start(BASE_REGION)
  p.alone = start(ALONE_REGION)
end

local function settled()
  local p, surface = storage.personal, game.surfaces.nauvis
  local here = rig.offset(rig.region(BASE_REGION), 6, 0)
  local mobile = 0
  for _, network in pairs(surface.find_logistic_networks_by_construction_area(here, rig.FORCE)) do
    local cell = network.find_cell_closest_to(here)
    if cell and cell.mobile then mobile = mobile + 1 end
  end
  check.eq("personal the character's roboport reaches the project", mobile, 1)
  local b = rig.call("get_project", p.base)
  check.eq("personal grows on the base's stock beside a personal roboport", b and b.count, 3,
    b and check.show(b.status))
  local a = rig.call("get_project", p.alone)
  local s = a and a.status
  check.eq("personal alone: its pockets decide", s and s.reason, "missing-materials", s and check.show(s))
  check.eq("personal alone: what the pockets can spare", s and s.item and s.item.have, 1)
end

case.checks = { [1500] = settled }

return case
