-- Cliffs under a copy. Only a cliff under a part (an entity part's collision
-- box, a design tile) or under a Keep clear tile stops a copy; one in an empty
-- gap of its footprint does not. A team that has researched cliff
-- explosives (LuaForce.cliff_deconstruction_enabled) has such a cliff blown
-- up instead: the check notes it (plan.cliffs counts the explosives, which
-- the materials gate waits for), and after the stamp it is ordered for
-- removal, so robots bring the explosive. A forced paste marks the cliffs
-- its entity ghosts collide with by itself; tiles collide with no cliff, so
-- the cliffs under design tiles and Keep clear tiles need the order. A stamp
-- that is rolled back takes the paste's marks back (clearing.unmarked).

local const = require("scripts.const")
local geometry = require("scripts.core.geometry")
local under = require("scripts.core.under")

local cliffs = {}

-- Per cliff name, constant for the session: the item that removes it (false
-- when none does).
local explosives = {}

local function explosive_of(name)
  local item = explosives[name]
  if item == nil then
    item = prototypes.entity[name].cliff_explosive_prototype or false
    explosives[name] = item
  end
  return item
end

-- The item that removes the cliff, when the force may remove it.
function cliffs.explosive(force, cliff)
  if not force.cliff_deconstruction_enabled then return nil end
  return explosive_of(cliff.name) or nil
end

-- A cliff under the plan: noted for the stamp, or nil and the reason and
-- place it stops the copy.
function cliffs.note(plan, force, cliff)
  local item = cliffs.explosive(force, cliff)
  if not item then return const.REASON.cliff, cliff.position end
  local key = geometry.position_key(cliff.position)
  plan.cliff_entities = plan.cliff_entities or {}
  if plan.cliff_entities[key] then return nil end
  plan.cliff_entities[key] = cliff
  plan.cliffs = plan.cliffs or {}
  plan.cliffs[item] = (plan.cliffs[item] or 0) + 1
end

-- Notes the cliffs under the boxes; nil, or the reason and position of the
-- first one that stops the plan.
function cliffs.under(surface, force, plan, boxes)
  local reason, where
  under.each(surface, nil, boxes, { type = "cliff" }, function(cliff)
    reason, where = cliffs.note(plan, force, cliff)
    if reason then return under.STOP end
  end)
  return reason, where
end

-- After a stamp: every cliff the check noted and the paste did not mark is
-- ordered for removal.
function cliffs.order(plan, force)
  for _, cliff in pairs(plan.cliff_entities or {}) do
    if cliff.valid and not cliff.to_be_deconstructed() then cliff.order_deconstruction(force) end
  end
end

return cliffs
