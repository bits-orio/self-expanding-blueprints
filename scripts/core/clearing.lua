-- Clearing an area (DESIGN.md: the builder's Clear verb and the remote
-- clear): order deconstruction of everything of a force in a box, trees and
-- rocks included, optionally only what given items build; or cancel those
-- orders.

local under = require("scripts.core.under")

local clearing = {}

local NATURE_TYPES = { "tree", "simple-entity" }
local NATURE_AND_CLIFFS = { "tree", "simple-entity", "cliff" }

-- What a forced paste of the plan by `force` may mark for removal and is not
-- marked yet, so that a stamp rolled back, or a look-only paste, can take
-- those orders back (clearing.take_back): what stands under its entity
-- parts (tiles mark nothing), trees and rocks, cliffs when the force may
-- blow them up, and superforced, the force's own entities.
function clearing.unmarked(surface, force, plan, superforced)
  local boxes, list = under.boxes(plan, "entities"), {}
  local function keep(e) list[#list + 1] = e end
  local types = force.cliff_deconstruction_enabled and NATURE_AND_CLIFFS or NATURE_TYPES
  under.each(surface, nil, boxes, { type = types, to_be_deconstructed = false }, keep)
  if superforced then under.each(surface, nil, boxes, { force = force, to_be_deconstructed = false }, keep) end
  return list
end

-- Cancels the removal orders `force` gave since clearing.unmarked: a stamp
-- rolled back, or a look-only paste, leaves trees, rocks and buildings be.
function clearing.take_back(list, force)
  for _, e in ipairs(list) do
    if e.valid and e.to_be_deconstructed() then e.cancel_deconstruction(force) end
  end
end

local NATURE = { tree = true, ["simple-entity"] = true }

local function wanted(entity, filter)
  if not filter then return true end
  for _, item in pairs(entity.prototype.items_to_place_this or {}) do
    if filter[item.name] then return true end
  end
  return false
end

-- opts: surface, force, box ({{x, y}, {x, y}}), filter ({[item] = true} or
-- nil), cancel, skip ({[entity] = true} never touched). Returns the
-- entities ordered (or already ordered), none when cancelling.
function clearing.run(opts)
  local surface, force, skip = opts.surface, opts.force, opts.skip or {}
  local list = surface.find_entities_filtered { area = opts.box, force = force }
  for _, e in pairs(surface.find_entities_filtered { area = opts.box, type = { "tree", "simple-entity" } }) do
    list[#list + 1] = e
  end
  local pending = {}
  for _, e in pairs(list) do
    local ours = not skip[e.unit_number or -1] and e.type ~= "character"
    if ours and (NATURE[e.type] or e.force == force) and wanted(e, opts.filter) then
      if opts.cancel then
        if e.to_be_deconstructed() then e.cancel_deconstruction(force) end
      elseif e.to_be_deconstructed() or e.order_deconstruction(force) then
        pending[#pending + 1] = e
      end
    end
  end
  return pending
end

return clearing
