-- Probes: tile markers that say what must be true under them before a design
-- is stamped there (DESIGN.md "Probes and rules"). The signals set in a
-- probe say what:
--   no signal                 some resource under the tile
--   resource signals          one of these resources: an entity signal names
--                             a resource, an item or fluid signal the
--                             resources that yield it (iron ore, crude oil)
--   the fluid signal water    a water tile
--   building signals          one of these buildings of the copy's own team:
--                             an entity signal names one, an item signal the
--                             building it places (a pole, a chest)
--   plus the signal "deny"    the opposite: none of these
-- Several kinds in one probe hold when any of them is there. The blueprint
-- builder's sense signals narrow a probe to their kinds, the signals above
-- then naming which of a kind (ghosts and a pole: a ghost of a pole):
--   buildings and ghosts (both the team's own), resources, trees and rocks,
--   water, enemies.
-- A probe that does not hold closes the socket with the reason "probe" (or,
-- for a pool, moves on to the next design).

local const = require("scripts.const")
local signals = require("scripts.core.signals")
local placement = require("scripts.core.placement")

local probes = {}

local DENY = "signal-deny"
local KINDS = {
  "seb-sense-entities", "seb-sense-ghosts", "seb-sense-resources", "seb-sense-trees", "seb-sense-water",
  "seb-sense-enemies",
}

-- Resource names by what they yield, built once per session (prototypes
-- cannot change while the game runs).
local yields
local function resources_yielding(kind, name)
  if not yields then
    yields = {}
    for resource_name, proto in pairs(prototypes.get_entity_filtered { { filter = "type", type = "resource" } }) do
      for _, product in ipairs(proto.mineable_properties.products or {}) do
        local key = product.type .. "/" .. product.name
        yields[key] = yields[key] or {}
        table.insert(yields[key], resource_name)
      end
    end
  end
  return yields[kind .. "/" .. name] or {}
end

-- The building an item or entity signal names, or nil.
local function building_of(s)
  if s.type == "entity" then
    local proto = prototypes.entity[s.name]
    return proto and proto.type ~= "resource" and s.name or nil
  end
  local item = s.type == "item" and prototypes.item[s.name]
  local placed = item and item.place_result
  return placed and placed.type ~= "resource" and placed.name or nil
end

-- What a probe marker asks for: {water = bool, resources = {names} or nil,
-- buildings = {names} or nil, negate = bool}; with none of the three, any
-- resource.
-- The sense kinds set in a probe, as a set, or nil for none.
local function kinds_of(entity)
  local kinds
  for _, name in ipairs(KINDS) do
    if signals.virtual(entity, name) then
      kinds = kinds or {}
      kinds[name] = true
    end
  end
  return kinds
end

-- A list, or nil when empty.
local function some(list)
  return #list > 0 and list or nil
end

function probes.read(entity)
  local probe = {
    position = entity.position, negate = signals.virtual(entity, DENY) ~= nil, water = false, kinds = kinds_of(entity),
  }
  -- Without kinds an item names the ore that yields it, else the building
  -- it places; a kind says which of the two it names.
  local names, built, yields, places = {}, {}, {}, {}
  for _, s in ipairs(signals.named(entity)) do
    local yielded = (s.type == "item" or s.type == "fluid") and resources_yielding(s.type, s.name) or {}
    local placed = building_of(s)
    if s.type == "entity" and prototypes.entity[s.name] and prototypes.entity[s.name].type == "resource" then
      yielded = { s.name }
    end
    for _, r in ipairs(yielded) do yields[#yields + 1] = r end
    if placed then places[#places + 1] = placed end
    if s.type == "fluid" and s.name == "water" then
      probe.water = true
    elseif #yielded > 0 then
      for _, r in ipairs(yielded) do names[#names + 1] = r end
    elseif placed then
      built[#built + 1] = placed
    end
  end
  probe.resources, probe.buildings = some(names), some(built)
  if probe.kinds then probe.yields, probe.places = some(yields), some(places) end
  return probe
end

local function tile_area(x, y)
  return { { x, y }, { x + 1, y + 1 } }
end

local function any_resource(surface, x, y, names)
  return surface.count_entities_filtered { area = tile_area(x, y), type = "resource", name = names, limit = 1 } > 0
end

local function count(surface, x, y, filter)
  filter.area, filter.limit = tile_area(x, y), 1
  return surface.count_entities_filtered(filter) > 0
end

-- Whether one sense kind is on the tile, narrowed by the probe's names.
local FOUND = {
  ["seb-sense-entities"] = function(surface, force, probe, x, y)
    if probe.places then return count(surface, x, y, { name = probe.places, force = force }) end
    local area = tile_area(x, y)
    local all = surface.count_entities_filtered { area = area, force = force }
    return all > surface.count_entities_filtered { area = area, force = force, type = "entity-ghost" }
  end,
  ["seb-sense-ghosts"] = function(surface, force, probe, x, y)
    return count(surface, x, y, { type = "entity-ghost", ghost_name = probe.places, force = force })
  end,
  ["seb-sense-resources"] = function(surface, _, probe, x, y)
    return count(surface, x, y, { type = "resource", name = probe.yields })
  end,
  ["seb-sense-trees"] = function(surface, _, _, x, y)
    return count(surface, x, y, { type = { "tree", "simple-entity" } })
  end,
  ["seb-sense-water"] = function(surface, _, _, x, y)
    return surface.get_tile(x, y).collides_with("water_tile")
  end,
  ["seb-sense-enemies"] = function(surface, _, _, x, y)
    return count(surface, x, y, { force = "enemy" })
  end,
}

local function found_at(surface, force, probe, x, y)
  if probe.kinds then
    for kind in pairs(probe.kinds) do
      if FOUND[kind](surface, force, probe, x, y) then return true end
    end
    return false
  end
  if not (probe.water or probe.resources or probe.buildings) then return any_resource(surface, x, y) end
  if probe.water and surface.get_tile(x, y).collides_with("water_tile") then return true end
  if probe.resources and any_resource(surface, x, y, probe.resources) then return true end
  return probe.buildings ~= nil and surface.count_entities_filtered {
    area = tile_area(x, y), name = probe.buildings, force = force, limit = 1,
  } > 0
end

local function holds(surface, force, probe, x, y)
  return found_at(surface, force, probe, x, y) ~= probe.negate
end

-- nil when every probe of the plan holds; else "probe" and where one fails.
-- Either way it also gives how many probes it looked at, an engine count
-- each, so the spot pays for them whatever the verdict (work.lua).
function probes.check(surface, plan, force)
  local list = plan.prepared.probes or {}
  for i, probe in ipairs(list) do
    local p = placement.world(plan.prepared, probe.position, plan.position, plan.direction)
    local x, y = math.floor(p.x), math.floor(p.y)
    if not holds(surface, force, probe, x, y) then return const.REASON.probe, { x = x + 0.5, y = y + 0.5 }, i end
  end
  return nil, nil, #list
end

return probes
