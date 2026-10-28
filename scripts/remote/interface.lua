-- The remote interface "self-expanding-blueprints" (DESIGN.md section 6;
-- parameters in docs/remote-interface.md). A draft until v1: names and
-- shapes may still change before it is stable. Forces and surfaces may be
-- given as LuaForce/LuaSurface, name or index.

local const = require("scripts.const")
local projects = require("scripts.core.projects")
local twins = require("scripts.core.twins")
local instances = require("scripts.core.instances")
local growth = require("scripts.core.growth")
local update = require("scripts.core.update")
local clearing = require("scripts.core.clearing")
local events = require("scripts.remote.events")
local args = require("scripts.remote.args")
local lookup = require("scripts.remote.lookup")
local limits = require("scripts.core.limits")
local limit_changes = require("scripts.limit_changes")

local function resolve(params)
  if type(params) ~= "table" then return nil, "invalid-params" end
  local force, surface = lookup.force(params.force), lookup.surface(params.surface)
  if not force then return nil, "unknown-force" end
  if not surface then return nil, "unknown-surface" end
  local design = lookup.design(force.index, params.design)
  if not design then return nil, const.REASON.unknown_design end
  return force, surface, design
end

local STAMP_FIELDS = { "position", "build_position", "direction", "charted_only", "materials" }
local STAMP_PLACES = { "position", "build_position" }
local PROJECT_FIELDS = {
  "position", "build_position", "point", "area", "direction", "directions", "max_instances", "materials",
  "reserve", "max_building", "charted_only", "retire_depleted", "dry_run", "order", "radius",
  "enemy_distance", "landfill", "open_early", "superforce", "preview_ghosts", "mirrored",
}
local PROJECT_PLACES = { "position", "build_position", "point", "area" }

local interface = {}

-- params: force, surface, design (id or name), position or build_position,
-- direction, charted_only, materials.
function interface.stamp(params)
  local force, surface, design = resolve(params)
  if not force then return nil, surface end
  local opts, reason = args.read(params, STAMP_FIELDS, STAMP_PLACES)
  if not opts then return nil, reason end
  local result = growth.stamp_once({
    force_index = force.index, surface_index = surface.index, design_id = design.id,
    charted_only = opts.charted_only == true, materials = opts.materials == true,
  }, opts, opts.direction or defines.direction.north)
  if result.kind ~= "stamped" then return nil, result.reason, result.position end
  return result.instance.id
end

function interface.remove_instance(instance_id)
  local instance = storage.instances[instance_id]
  if not instance then return false, "unknown-instance" end
  return instances.retire(instance)
end

function interface.get_instance(instance_id)
  local instance = storage.instances[instance_id]
  return instance and instances.summary(instance)
end

local function ids_of(list)
  if not list then return nil end
  local ids = {}
  for i, project in ipairs(list) do ids[i] = project.id end
  return ids
end

-- params: force, surface, design, and one of position, build_position, point
-- or area; direction, directions, max_instances, materials, reserve,
-- max_building, charted_only, retire_depleted, dry_run, order, radius,
-- enemy_distance, landfill, open_early, superforce, preview_ghosts
-- (docs/remote-interface.md).
-- Returns the project's id and, for a dry run, the ids of the plans stopped
-- to make room for it (limits "plans"), or nil; or nil and a reason.
function interface.start_project(params)
  local force, surface, design = resolve(params)
  if not force then return nil, surface end
  local opts, reason = args.read(params, PROJECT_FIELDS, PROJECT_PLACES)
  if not opts then return nil, reason end
  -- Mirrored, the design's mirror twin grows (twins.lua).
  if opts.mirrored then
    local twin, why = twins.of(design)
    if not twin then return nil, why end
    design = twin
  end
  opts.force_index, opts.surface_index, opts.design_id = force.index, surface.index, design.id
  local project, other = projects.start(opts)
  if not project then return nil, other end
  return project.id, ids_of(other)
end

function interface.get_project(project_id)
  local project = storage.projects[project_id]
  return project and projects.summary(project)
end

function interface.pause_project(project_id)
  local project = storage.projects[project_id]
  return project ~= nil and projects.pause(project)
end

function interface.resume_project(project_id)
  local project = storage.projects[project_id]
  return project ~= nil and projects.resume(project)
end

function interface.stop_project(project_id)
  local project = storage.projects[project_id]
  if project then projects.stop(project) end
  return project ~= nil
end

-- params: force, surface, area (any of the three area forms), items (a list
-- of item names: only what they build), cancel. Orders deconstruction of
-- everything of the force in the area, trees and rocks included (or cancels
-- those orders). Returns how many entities are ordered.
function interface.clear(params)
  if type(params) ~= "table" then return nil, "invalid-params" end
  local force, surface = lookup.force(params.force), lookup.surface(params.surface)
  if not force then return nil, "unknown-force" end
  if not surface then return nil, "unknown-surface" end
  local area = args.area(params.area)
  if not area then return nil, "invalid-area" end
  local filter
  if type(params.items) == "table" and #params.items > 0 then
    filter = {}
    for _, name in ipairs(params.items) do filter[name] = true end
  end
  local pending = clearing.run {
    surface = surface, force = force, box = { { area.left, area.top }, { area.right, area.bottom } },
    filter = filter, cancel = params.cancel == true,
  }
  return #pending
end

-- Moves a copy to its design's current version in place. Returns true, or
-- false and why not ("unknown-instance", "up-to-date", "misaligned",
-- "building", "joined", "unknown-design", "invalid-design").
function interface.update_instance(instance_id)
  local instance = storage.instances[instance_id]
  if not instance then return false, "unknown-instance" end
  return update.run(instance)
end

-- Queues every outdated copy of a project for update in place (a few per
-- run of the due-tick queue, within the force's share of server time);
-- returns how many were queued, and 0. How many are updated and refused
-- goes into the project's history once the last has had its turn.
function interface.update_project(project_id)
  local project = storage.projects[project_id]
  if not project then return 0, 0 end
  return projects.update_copies(project)
end

-- A finished dry run, grown for real. Returns the new project's id, or nil
-- and why not ("not-found", "not-a-finished-plan", or a start refusal).
function interface.build_project(project_id)
  local project = storage.projects[project_id]
  if not project then return nil, "not-found" end
  local real, reason = projects.build(project)
  if not real then return nil, reason end
  return real.id
end

function interface.get_event_id(name)
  return events[name]
end

-- The map's limits for one force, overridden ({projects = 5, work = 200,
-- ...}; limits.lua names the keys). What waited on the old values looks
-- again at once (limit_changes.lua). Returns true, or nil and why not.
function interface.set_limits(force, overrides)
  local f = lookup.force(force)
  if not f then return nil, "unknown-force" end
  if type(overrides) ~= "table" then return nil, "invalid-params" end
  local ok, key = limits.set(f.index, overrides)
  if not ok then return nil, "invalid-" .. tostring(key) end
  limit_changes.of_force(f.index, overrides)
  return true
end

-- Every limit as it applies to the force now, or nil and why not.
function interface.get_limits(force)
  local f = lookup.force(force)
  if not f then return nil, "unknown-force" end
  return limits.all(f.index)
end

-- Drops the force's overrides: the map settings apply again.
function interface.clear_limits(force)
  local f = lookup.force(force)
  if not f then return nil, "unknown-force" end
  limits.clear(f.index)
  limit_changes.of_force(f.index)
  return true
end

require("scripts.remote.designs")(interface)
require("scripts.remote.agent")(interface)
remote.add_interface(const.MOD, interface)

return interface
