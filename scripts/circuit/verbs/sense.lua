-- Sense: count one category in the rectangle X, Y, W, H and show the counts
-- with DONE. Categories (one per request): entities and ghosts of the
-- builder's force as the items that place them, resources as what they
-- yield (amounts), and trees and rocks, water tiles or enemy buildings as a
-- count on the category's own signal. A big rectangle is counted a piece
-- per chunk over a few reads (sweep.lua), to the same totals.

local budget = require("scripts.core.budget")
local answer = require("scripts.circuit.answer")
local sweep = require("scripts.circuit.verbs.sweep")

local sense = {}

local virtual = answer.virtual
local MAX_TILES = 512 * 512
local PER_ENTITY = budget.COST.check_part

local function add(values, key, n)
  values[key] = answer.clamp((values[key] or 0) + n)
end

-- Per prototype name, constant for the session (prototypes cannot change
-- while the script runs, and these are rebuilt on every load): the item
-- that places an entity (false for none), what a resource yields.
local item_names, product_keys = {}, {}

local function item_of(name)
  local item = item_names[name]
  if item == nil then
    local items = prototypes.entity[name].items_to_place_this
    item = items and items[1] and items[1].name or false
    item_names[name] = item
  end
  return item
end

local function products_of(name)
  local keys = product_keys[name]
  if not keys then
    keys = {}
    for _, product in ipairs(prototypes.entity[name].mineable_properties.products or {}) do
      keys[#keys + 1] = product.type .. "/" .. product.name
    end
    product_keys[name] = keys
  end
  return keys
end

-- Each category counts one piece into its values and returns how many
-- entities it looked at. at: surface, area, force, values, and owns(position),
-- whether an entity found belongs to this piece (sweep.owns).
local function placed(at, filter, name_of)
  local found = at.surface.find_entities_filtered(filter)
  for _, e in pairs(found) do
    local name = name_of(e)
    local item = name and item_of(name)
    if item and at.owns(e.position) then add(at.values, "item/" .. item, 1) end
  end
  return #found
end

-- A building's own name; a ghost is no building.
local function built_name(e)
  return e.type ~= "entity-ghost" and e.name or nil
end

local function ghost_name(e)
  return e.ghost_name
end

-- A count on the category's own signal, of what `filter` finds.
local function counted(name, filter)
  return function(at)
    filter.area = at.area
    local found = at.surface.find_entities_filtered(filter)
    local n = 0
    for _, e in pairs(found) do
      if at.owns(e.position) then n = n + 1 end
    end
    add(at.values, virtual(name), n)
    return #found
  end
end

local function resources(at)
  local found = at.surface.find_entities_filtered { area = at.area, type = "resource" }
  for _, r in pairs(found) do
    if at.owns(r.position) then
      local amount = r.amount
      for _, key in ipairs(products_of(r.name)) do add(at.values, key, amount) end
    end
  end
  return #found
end

local COUNT = {
  ["seb-sense-entities"] = function(at)
    return placed(at, { area = at.area, force = at.force }, built_name)
  end,
  ["seb-sense-ghosts"] = function(at)
    return placed(at, { area = at.area, force = at.force, type = "entity-ghost" }, ghost_name)
  end,
  ["seb-sense-resources"] = resources,
  ["seb-sense-trees"] = counted("seb-sense-trees", { type = { "tree", "simple-entity" } }),
  ["seb-sense-water"] = function(at)
    add(at.values, virtual("seb-sense-water"), at.surface.count_tiles_filtered { area = at.area, collision_mask = "water_tile" })
    return 0
  end,
  ["seb-sense-enemies"] = counted("seb-sense-enemies", { force = "enemy" }),
}

local function category(input)
  local found
  for name in pairs(COUNT) do
    if input.virtual[name] then
      if found then return nil end
      found = name
    end
  end
  return found
end

function sense.start(b, request, input)
  local name = category(input)
  local area = answer.area(b, input, MAX_TILES)
  if not (name and area) then return answer.fail(b, "invalid") end
  request.category, request.values = name, {}
  sweep.begin(request, area)
  sense.tick(b, request)
end

function sense.tick(b, request)
  local surface, force, count = b.entity.surface, b.entity.force, COUNT[request.category]
  local done = sweep.run(request, b.force_index, function(p)
    local at = { surface = surface, area = sweep.area(p), force = force, values = request.values }
    function at.owns(position) return sweep.owns(request, p, position) end
    return count(at) * PER_ENTITY
  end)
  if done then answer.done(b, request.values) end
end

return sense
