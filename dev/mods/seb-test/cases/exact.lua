-- exact.lua: an instance tracks exactly its own entities, however they come
-- and go, so retiring it removes exactly those.
--   tiles:     retiring while building destroys its tile ghosts too
--   paste:     a blueprint taken over in-flight ghosts copies their tag; its
--              paste elsewhere never joins the instance
--   death:     a death ghost removed unbuilt ends the instance incomplete
--   revive:    a ghost revived without raise_revive is still adopted
--   upgrade:   robots upgrade a stamped belt; retiring removes the upgrade

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "exact" }

local SYNC_REGION, ROBOT_REGION = 15, 16
local D = defines.direction

local CHEST = { { name = "iron-chest", position = { x = 0.5, y = 0.5 } } }
local PAIR = { CHEST[1], { name = "iron-chest", position = { x = 2.5, y = 0.5 } } }
local PAVED_TILES = {
  { name = "stone-path", position = { x = 0, y = 0 } }, { name = "stone-path", position = { x = 1, y = 0 } },
  { name = "stone-path", position = { x = 0, y = 1 } }, { name = "stone-path", position = { x = 1, y = 1 } },
}
local BELTS = {
  { name = "transport-belt", position = { x = 0.5, y = 0.5 }, direction = D.east },
  { name = "transport-belt", position = { x = 1.5, y = 0.5 }, direction = D.east },
}

local function stamp(surface, design, at)
  local id, reason = rig.call("stamp", { force = rig.FORCE, surface = surface, design = design, position = at })
  check.truthy("exact stamp design " .. design, id, reason)
  return id
end

local function area_of(id)
  local fp = rig.call("get_instance", id).footprint
  return { { fp.left, fp.top }, { fp.right, fp.bottom } }
end

-- `filter.area` is given for a copy that is gone: a retired copy is forgotten (D45).
local function find(surface, id, filter)
  filter.area = filter.area or area_of(id)
  return surface.find_entities_filtered(filter)
end

local function state_of(id)
  local inst = rig.call("get_instance", id)
  return inst and inst.state
end

local function tiles_case(surface, o)
  local id = stamp(surface, rig.design(CHEST, "Exact paved", { tiles = PAVED_TILES }), rig.offset(o, 0, 0))
  if not id then return end
  check.eq("exact tile ghosts placed", #find(surface, id, { type = "tile-ghost" }), 4)
  local area = area_of(id)
  local ok, reason = rig.call("remove_instance", id)
  check.truthy("exact retire while building accepted", ok, reason)
  check.eq("exact retired at once, then forgotten", state_of(id), nil)
  check.eq("exact retire destroys tile ghosts", #find(surface, id, { type = "tile-ghost", area = area }), 0)
  check.eq("exact retire destroys entity ghosts", #find(surface, id, { type = "entity-ghost", area = area }), 0)
end

-- Copies the instance's in-flight ghost into a blueprint, pastes it 10 tiles
-- south and revives the paste the way a script would announce it.
local function paste_copy(surface, id, at)
  local inventory = game.create_inventory(1)
  local bp = inventory[1]
  bp.set_stack { name = "blueprint" }
  bp.create_blueprint { surface = surface, force = rig.FORCE, area = area_of(id) }
  check.eq("exact blueprint captured the tag", bp.get_blueprint_entity_tag(1, "seb_instance"), id)
  local pasted = bp.build_blueprint { surface = surface, force = rig.FORCE, position = at, build_mode = defines.build_mode.forced }
  inventory.destroy()
  for _, ghost in pairs(pasted) do ghost.revive { raise_revive = true } end
end

local function paste_case(surface, o)
  local id = stamp(surface, rig.design(CHEST, "Exact chest"), rig.offset(o, 10, 0))
  if not id then return end
  paste_copy(surface, id, rig.offset(o, 10, 10))
  check.eq("exact paste is not adopted", rig.call("get_instance", id).entity_count, 0)
  rig.call("remove_instance", id)
  local chest = surface.find_entities_filtered { area = { rig.offset(o, 9, 9), rig.offset(o, 13, 12) }, name = "iron-chest" }[1]
  check.truthy("exact paste survives the retire", chest and not chest.to_be_deconstructed(), check.show(chest and chest.valid))
end

-- Both chests built, then one dies: its death ghost is the only thing left.
local function death_case(surface, o, e)
  e.death = stamp(surface, rig.design(PAIR, "Exact pair"), rig.offset(o, 20, 0))
  if not e.death then return end
  for _, ghost in pairs(find(surface, e.death, { type = "entity-ghost" })) do ghost.revive { raise_revive = true } end
  find(surface, e.death, { name = "iron-chest" })[1].die()
end

function case.setup(surface)
  local o = rig.region(SYNC_REGION)
  rig.floor(surface, rig.box(o, -10, -10, 60, 30))
  game.forces[rig.FORCE].create_ghost_on_entity_death = true
  local e = {}
  storage.exact = e
  tiles_case(surface, o)
  paste_case(surface, o)
  death_case(surface, o, e)
  e.revive = stamp(surface, rig.design(CHEST, "Exact chest"), rig.offset(o, 30, 0))
  if e.revive then find(surface, e.revive, { type = "entity-ghost" })[1].revive() end
  local r = rig.region(ROBOT_REGION)
  rig.floor(surface, rig.box(r, -60, -60, 60, 60))
  rig.network(surface, rig.offset(r, -20, -20), { { "transport-belt", 20 }, { "fast-transport-belt", 20 } })
  e.belts = stamp(surface, rig.design(BELTS, "Exact belts"), rig.offset(r, 10.5, 10.5))
end

-- After the first recount has counted the death ghost: remove it unbuilt.
function case.start(surface)
  local e = storage.exact
  check.eq("exact death ghost still pending", state_of(e.death), "building")
  local fp = rig.call("get_instance", e.death).footprint
  local drawn = rig.drawn(surface, { left = fp.left - 1, top = fp.top - 1, right = fp.right + 1, bottom = fp.bottom + 1 })
  check.same("exact building instance drawn as outline and label", { drawn.rectangle, drawn.text }, { 1, 1 })
  for _, ghost in pairs(find(surface, e.death, { type = "entity-ghost" })) do ghost.destroy() end
end

local function settled(surface)
  local e = storage.exact
  check.eq("exact removed death ghost ends incomplete", state_of(e.death), "incomplete")
  check.eq("exact silent revive completes", state_of(e.revive), "complete")
  check.eq("exact silent revive adopted", rig.call("get_instance", e.revive).entity_count, 1)
  check.eq("exact belts complete", state_of(e.belts), "complete")
  for _, belt in pairs(find(surface, e.belts, { name = "transport-belt" })) do
    belt.order_upgrade { target = "fast-transport-belt", force = rig.FORCE }
  end
end

local function upgraded(surface)
  local e = storage.exact
  check.eq("exact belts upgraded", #find(surface, e.belts, { name = "fast-transport-belt" }), 2)
  check.eq("exact upgrades adopted", rig.call("get_instance", e.belts).entity_count, 2)
  e.belts_area = area_of(e.belts)
  rig.call("remove_instance", e.belts)
end

local function removed(surface)
  local e = storage.exact
  check.eq("exact upgraded belts retired, then forgotten", state_of(e.belts), nil)
  check.eq("exact no belt left", #find(surface, e.belts, { type = "transport-belt", area = e.belts_area }), 0)
end

case.checks = { [1200] = settled, [2400] = upgraded, [3600] = removed }

return case
