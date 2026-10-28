-- Probes: tile markers that say what must be true under them before a design
-- is stamped there (DESIGN.md "Probes and rules"). The signals set in a
-- probe say what:
--   no signal                 some resource under the tile
--   resource signals          one of these resources: an entity signal names
--                             a resource, an item or fluid signal the
--                             resources that yield it (iron ore, crude oil)
--   the fluid signal water    a water tile
--   plus the signal "deny"    the opposite: none of these, or no water
-- A probe that does not hold closes the socket with the reason "probe" (or,
-- for a pool, moves on to the next design).

local const = require("scripts.const")
local signals = require("scripts.core.signals")
local placement = require("scripts.core.placement")

local probes = {}

local DENY = "signal-deny"

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

-- What a probe marker asks for: {water = bool, resources = {names} or nil
-- (any), negate = bool}.
function probes.read(entity)
  local probe = { position = entity.position, negate = signals.virtual(entity, DENY) ~= nil, water = false }
  local names = {}
  for _, s in ipairs(signals.named(entity)) do
    if s.type == "fluid" and s.name == "water" then
      probe.water = true
    elseif s.type == "entity" and prototypes.entity[s.name] and prototypes.entity[s.name].type == "resource" then
      names[#names + 1] = s.name
    elseif s.type == "item" or s.type == "fluid" then
      for _, r in ipairs(resources_yielding(s.type, s.name)) do names[#names + 1] = r end
    end
  end
  if #names > 0 then probe.resources = names end
  return probe
end

local function tile_area(x, y)
  return { { x, y }, { x + 1, y + 1 } }
end

local function holds(surface, probe, x, y)
  local found
  if probe.water then
    found = surface.get_tile(x, y).collides_with("water_tile")
  else
    found = surface.count_entities_filtered {
      area = tile_area(x, y), type = "resource", name = probe.resources, limit = 1,
    } > 0
  end
  return found ~= probe.negate
end

-- nil when every probe of the plan holds; else "probe" and where one fails.
-- Either way it also gives how many probes it looked at, an engine count
-- each, so the spot pays for them whatever the verdict (work.lua).
function probes.check(surface, plan)
  local list = plan.prepared.probes or {}
  for i, probe in ipairs(list) do
    local p = placement.world(plan.prepared, probe.position, plan.position, plan.direction)
    local x, y = math.floor(p.x), math.floor(p.y)
    if not holds(surface, probe, x, y) then return const.REASON.probe, { x = x + 0.5, y = y + 0.5 }, i end
  end
  return nil, nil, #list
end

return probes
