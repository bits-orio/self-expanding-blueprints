-- Whether an update in place (update.lua) may be built where it is laid.
-- Everything the new version needs must be placeable before anything of the
-- copy goes: built superforced, the copy's own parts in the way do not count,
-- but another copy's footprint, anyone else's building or ghost, water
-- (unless the copy's project superforces), cliffs, missing ore and unheld
-- land do. A part that already stands stays as it is (update_match.lua), so
-- only the fresh parts, the design's tiles and its Keep clear tiles are
-- looked at: the work follows what changes, never the footprint's area.

local const = require("scripts.const")
local footprints = require("scripts.core.footprints")
local checks = require("scripts.core.checks")
local under = require("scripts.core.under")

local update_fit = {}

local REASON = const.REASON

-- Things that pass through rather than stand: never in an update's way, so
-- the engine leaves them out of the search.
local STANDING = {
  type = {
    "construction-robot", "logistic-robot", "combat-robot", "car", "spider-vehicle", "locomotive", "cargo-wagon",
    "fluid-wagon", "artillery-wagon", "character", "item-request-proxy", "corpse", "item-entity",
  },
  invert = true,
}

-- Whether a prototype is a building (trees, rocks and ore are not: a forced
-- build marks or builds over them), by name: constant for the session
-- (prototypes cannot change while the script runs; rebuilt on every load).
local creation = {}

local function is_building(name)
  local known = creation[name]
  if known == nil then
    known = prototypes.entity[name].flags["player-creation"] == true
    creation[name] = known
  end
  return known
end

-- A building or ghost not of this copy, of any force.
local function foreign(instance, e)
  local unit = e.unit_number
  if unit and instance.entities[unit] then return false end
  if e.type == "entity-ghost" then
    local tags = e.tags
    return not (tags and tags[const.TAG] == instance.id)
  end
  return is_building(e.name)
end

-- The kinds of part a building may stand under (under.boxes).
local KINDS = { "entities", "tiles", "kept" }

local function foreign_in(surface, instance, plan)
  local found = false
  local function look(e)
    if not foreign(instance, e) then return nil end
    found = true
    return under.STOP
  end
  for _, kind in ipairs(KINDS) do
    under.each(surface, plan.footprint, under.boxes(plan, kind), STANDING, look)
    if found then return true end
  end
  return false
end

local function others_overlap(instance, footprint)
  for _, id in ipairs(footprints.overlapping(instance.surface_index, footprint)) do
    if id ~= instance.id then return true end
  end
  return false
end

-- The plan as the checks see it: its fresh parts only, every tile and Keep
-- clear tile still. It stands on water only as the copy's project grows
-- (water.lua): superforced, the engine lays landfill there.
local function fresh_only(plan, instance)
  local prepared = {}
  for k, v in pairs(plan.prepared) do prepared[k] = v end
  prepared.placements = plan.fresh
  local project = instance.project_id and storage.projects[instance.project_id]
  return {
    prepared = prepared, position = plan.position, direction = plan.direction, footprint = plan.footprint,
    superforce = true, cover_water = project ~= nil and project.superforce == true,
  }
end

local function placeable(surface, force, plan)
  local terrain = checks.terrain(surface, force, plan.footprint, { charted_only = false, generate = false })
  if terrain then return terrain.reason end
  return (checks.obstacles(surface, force, plan))
end

-- Why the new version cannot be built where `plan` lays it over the copy
-- (plan.fresh: its parts not standing yet), or nil and the plan as the
-- checks saw it, with what they noted for the build (cliffs to clear).
function update_fit.refusal(surface, instance, plan)
  if others_overlap(instance, plan.footprint) then return REASON.joined end
  local checked = fresh_only(plan, instance)
  if foreign_in(surface, instance, checked) then return REASON.building end
  local why = placeable(surface, game.forces[instance.force_index], checked)
  if why then return why end
  return nil, checked
end

return update_fit
