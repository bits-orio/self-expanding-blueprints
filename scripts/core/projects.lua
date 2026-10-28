-- Projects: one growth run each, started, paused, resumed and stopped here,
-- advanced by the growth loop (loop.lua) and told about its copies by
-- copy_events.lua. A project also keeps what a player needs to know why it
-- is where it is: the copies that are stalled right now, and a short
-- history (history.lua).

local const = require("scripts.const")
local registry = require("scripts.core.registry")
local library = require("scripts.core.library")
local geometry = require("scripts.core.geometry")
local placement = require("scripts.core.placement")
local footprints = require("scripts.core.footprints")
local history = require("scripts.core.history")
local status = require("scripts.core.status")
local loop = require("scripts.core.loop")
local overlay = require("scripts.render.overlay")
local previews = require("scripts.core.previews")
local gates = require("scripts.core.gates")
local update = require("scripts.core.update")
local update_queue = require("scripts.core.update_queue")
local limits = require("scripts.core.limits")
local instances = require("scripts.core.instances")
local retention = require("scripts.core.retention")

local projects = {}

-- changed(project): set by control.lua so open windows refresh.
projects.hooks = {}

local STATE = const.PROJECT_STATE
local REASON = const.REASON

local function changed(project)
  if projects.hooks.changed then projects.hooks.changed(project) end
end
loop.hooks.changed = changed

-- A project ended (stopped, or finished for real): nothing grows from its
-- copies retired for depletion any more, so their records go; the force's
-- oldest ended ones past what it keeps are forgotten, and their rows leave
-- the window (a row redraws only when its key changes, so the key is
-- cleared).
local function ended(project)
  instances.forget_retired_of(project.id)
  for _, gone in ipairs(retention.prune(project.force_index)) do
    gone.shown_key = nil
    changed(gone)
  end
end
loop.hooks.ended = ended

-- What started a project (plain data), kept so a dry run can be built as
-- planned.
local function copy_params(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = copy_params(v) end
  return out
end

local function new_project(params, design, seed, direction)
  return {
    id = registry.new_project_id(), force_index = params.force_index, surface_index = params.surface_index,
    design_id = design.id,
    -- Kept for designs with socket arrows too: a later version may have none.
    directions = params.directions or { geometry.EAST, geometry.SOUTH },
    rules = { max_instances = params.max_instances, area = params.area, charted_only = params.charted_only ~= false,
      generate = params.charted_only == false and params.generate ~= false and not params.dry_run,
      retire_depleted = params.retire_depleted == true, radius = params.radius, enemy_distance = params.enemy_distance,
      no_landfill = params.landfill == false },
    order = params.order or "breadth", seed_position = seed, open_early = params.open_early == true,
    superforce = params.superforce == true, preview_ghosts = params.dry_run and params.preview_ghosts or nil,
    gates = { materials = params.materials ~= false, reserve = params.reserve or 0,
      max_building = params.max_building or const.MAX_BUILDING, notify = true },
    frontier = { { kind = "seed", position = seed, direction = direction } }, parked = {},
    blocked = {}, closed = {}, instance_ids = {}, count = 0, building = 0,
    stalled = {}, waiting_ore = {}, history = {}, state = STATE.growing,
    dry_run = params.dry_run == true, planned = {}, plan_chunks = {}, start_params = copy_params(params),
    -- How the paste was turned (the window shows it): flipped, growing its
    -- designs' mirror twins; and grow-toward directions kept to the world.
    mirrored = params.mirrored == true, world_directions = params.world_directions == true,
    -- Who started it from the window, told if it builds nothing.
    player_index = params.player_index,
  }
end

-- A new plan always starts: when the force has as many live plans as it may
-- keep (limits "plans"), its oldest are stopped first, and their histories
-- say why. Returns them, or nil.
local function drop_plans_for(force_index)
  local dropped = retention.plans_to_drop(force_index)
  if #dropped == 0 then return nil end
  local cap = limits.of(force_index, "plans")
  for _, plan in ipairs(dropped) do
    history.add(plan, { kind = "replaced", limit = cap })
    projects.stop(plan)
  end
  return dropped
end

-- params: force_index, surface_index, design_id, one of
-- build_position, position, point or area (placement.seed), direction;
-- directions (implicit growth, default east and south), max_instances,
-- materials (default true), reserve, max_building, charted_only (default true),
-- retire_depleted (default false), dry_run (default false: plan as outlines),
-- order ("breadth", "depth" or "nearest"), radius (tiles from the seed),
-- enemy_distance (tiles to keep from enemy buildings), landfill (default
-- true; false refuses spots over water even where the design brings landfill),
-- open_early (default false: a copy's sockets open when it is placed, not
-- when it is built, for fast fills; raise max_building with it), superforce
-- (default false: buildings of the force in a copy's way are marked for
-- removal instead of closing the spot), preview_ghosts (a dry run's first
-- copies pasted as look-only ghosts, previews.lua), generate (default true
-- with charted_only false: land not generated yet is generated; a blueprint
-- builder passes false, and a dry run never generates, D43).
-- Returns the project and, for a plan, the plans stopped to make room for
-- it (or nil); or nil and why not. A plan never counts toward the force's
-- projects (limits "projects"), only toward its plans.
-- A project started a moment ago whose first copy is not stamped yet: its
-- seed holds its spot too, or a click right after it (grow, grow, grow)
-- could start a project on top of it. Only clicks pay for the walk.
local function seed_pending(surface_index, box)
  for _, project in pairs(storage.projects) do
    if project.count == 0 and project.seed_box and project.state == STATE.growing
      and project.surface_index == surface_index and geometry.overlaps(project.seed_box, box) then
      return true
    end
  end
  return false
end

function projects.start(params)
  local design = library.get(params.force_index, params.design_id)
  if not design then return nil, REASON.unknown_design end
  if not params.dry_run and not gates.may_start(params.force_index) then return nil, REASON.too_many_projects end
  local prepared = design.prepared
  if not (prepared and prepared.ok) then return nil, REASON.invalid_design end
  local direction = params.direction or geometry.NORTH
  if not geometry.is_cardinal(direction) then return nil, "invalid-direction" end
  local seed, reason = placement.seed(prepared, params, direction)
  if not seed then return nil, reason end
  -- A first copy over copies already there would end the project before it
  -- began (its spot closes as joined); a paste over identical buildings
  -- looks fine in hand, so it is refused here, where the player sees why;
  -- the copies in the way come third.
  local box = placement.footprint(prepared, seed, direction)
  local taken = footprints.overlapping(params.surface_index, box)
  if #taken > 0 then return nil, REASON.seed_occupied, taken end
  if seed_pending(params.surface_index, box) then return nil, REASON.seed_occupied end
  local dropped = params.dry_run and drop_plans_for(params.force_index) or nil
  local project = new_project(params, design, seed, direction)
  project.seed_box = box
  registry.add_project(project)
  history.add(project, { kind = "started", position = seed })
  loop.queue_advance(project, 1)
  changed(project)
  return project, dropped
end

-- `player` (optional) is who paused or resumed it, for the history.
function projects.pause(project, player)
  if project.state ~= STATE.growing then return false end
  project.state = STATE.paused
  history.add(project, { kind = "paused", player_index = player and player.index })
  overlay.refresh_project(project)
  changed(project)
  return true
end

function projects.resume(project, player)
  if project.state ~= STATE.paused then return false end
  project.state = STATE.growing
  history.add(project, { kind = "resumed", player_index = player and player.index })
  loop.queue_advance(project, 1)
  changed(project)
  return true
end

-- Queues every outdated copy to move to the design's current version in
-- place (update.lua), a few per run of the due-tick queue
-- (update_queue.lua). Returns how many joined the line, and 0: how many
-- are updated and how many refused goes into the history once the last
-- one has had its turn. `player` (optional) asked for it.
function projects.update_copies(project, player)
  local ids = {}
  for id in pairs(project.instance_ids) do
    local instance = storage.instances[id]
    if instance and update.outdated(instance) then ids[#ids + 1] = id end
  end
  table.sort(ids)
  local queued = update_queue.add(project.force_index, ids,
    { kind = "project", project_id = project.id, player_index = player and player.index })
  if queued > 0 then changed(project) end
  return queued, 0
end

-- The project's queued copies have all had their turn.
update_queue.done.project = function(batch)
  local project = storage.projects[batch.project_id]
  if not project then return end
  if batch.done + batch.refused > 0 then
    history.add(project, { kind = "updated", copies = batch.done, refused = batch.refused, player_index = batch.player_index })
  end
  changed(project)
end

-- A finished dry run becomes the real thing: a project with the same seed,
-- rules and gates, which grows the plan for real (and draws it as it goes).
function projects.build(project, player)
  if not (project.dry_run and project.state == STATE.finished) then return nil, "not-a-finished-plan" end
  local params = copy_params(project.start_params)
  params.dry_run, params.preview_ghosts = false, nil
  local real, reason = projects.start(params)
  if not real then return nil, reason end
  projects.stop(project)
  history.add(real, { kind = "built-plan", player_index = player and player.index })
  return real
end

-- Its copies stay, and robots finish the ones under construction; every
-- mark it drew leaves the map with it (overlay.lua draws nothing for them),
-- and nothing it asked for depletion (waiting for ore, removing dry
-- copies) happens any more. Its record stays among the force's ended
-- projects until newer ones push it out (retention.lua).
function projects.stop(project)
  project.state = STATE.stopped
  retention.let_go(project)
  project.gate, project.building = nil, 0
  project.planned, project.plan_chunks = {}, {}
  loop.wake_force(project.force_index)
  changed(project)
  ended(project)
end

function projects.list(force_index)
  local list = {}
  for id in pairs(registry.project_ids(force_index)) do
    local project = storage.projects[id]
    if project then list[#list + 1] = project end
  end
  table.sort(list, function(a, b) return a.id < b.id end)
  return list
end

-- How many of its copies are stalled right now.
function projects.stalled_count(project)
  return table_size(project.stalled or {})
end

local function nothing_built(note)
  if not note then return nil end
  local at = note.position
  return { reason = note.reason, position = at and { x = at.x, y = at.y } }
end

function projects.summary(project)
  local closed = {}
  for reason, n in pairs(project.closed) do closed[reason] = n end
  return {
    id = project.id, state = project.state, design_id = project.design_id, surface_index = project.surface_index,
    count = project.count, building = project.building, open_sockets = #project.frontier, parked = #project.parked,
    awaiting = #(project.awaiting or {}), gate = project.gate and project.gate.reason, blocked = #project.blocked,
    closed = closed, stalled = projects.stalled_count(project), waiting_ore = table_size(project.waiting_ore or {}),
    status = status.of(project), history = history.copy(project),
    nothing_built = nothing_built(project.nothing_built),
  }
end

-- Forget every project of a force or on a surface (force merged, surface
-- gone). Returns the set of force indexes that lost a project.
function projects.drop_where(predicate)
  local lost = {}
  for id, project in pairs(storage.projects) do
    if predicate(project) then
      previews.clear(project)
      overlay.drop_project(id)
      registry.remove_project(project)
      lost[project.force_index] = true
    end
  end
  return lost
end

return projects
