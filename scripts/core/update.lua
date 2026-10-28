-- Update in place (DESIGN.md section 5): a copy moves to its design's
-- current version without being torn down. The new version's stamping copy
-- is built superforced over the copy: a part both versions share stays (a
-- paste over an identical entity keeps it and takes the new settings), a
-- part only the new version has comes as a ghost, and a part only the old
-- one had is deconstructed. Something of anyone else's under the new
-- version's fresh parts refuses the update instead (update_fit.lua).
--
-- The new version goes where most of its parts coincide with the copy's
-- built entities (update_match.lua); the build position must then be on the
-- design's lattice, as for any stamp. Each update is one piece of work,
-- bounded by the design's parts and charged to the copy's force
-- (update.cost, budget.lua D44); many copies at once wait their turn in
-- update_queue.lua.

local const = require("scripts.const")
local geometry = require("scripts.core.geometry")
local placement = require("scripts.core.placement")
local library = require("scripts.core.library")
local footprints = require("scripts.core.footprints")
local instances = require("scripts.core.instances")
local tracking = require("scripts.core.tracking")
local ghosts = require("scripts.core.ghosts")
local depletion = require("scripts.core.depletion")
local clearance = require("scripts.core.clearance")
local budget = require("scripts.core.budget")
local update_match = require("scripts.core.update_match")
local update_fit = require("scripts.core.update_fit")
local under = require("scripts.core.under")
local spots = require("scripts.core.spots")
local water = require("scripts.core.water")

local update = {}

local STATE = const.STATE
local REASON = const.REASON
local COST = budget.COST

-- The build position that lays the new version at `shift`, or nil when it
-- falls off the lattice (build_blueprint would round it).
local function build_position(prepared, shift, direction)
  local o, lattice = prepared.offsets[direction], prepared.lattice or 1
  local p = { x = shift.x - o.x, y = shift.y - o.y }
  if p.x % lattice ~= 0 or p.y % lattice ~= 0 then return nil end
  return p
end

-- Where the new version goes over the copy, as the plan the checks and the
-- build share, with what it changes there (`fresh`: its parts not standing
-- yet; `dropped`: the copy's entities it no longer has); or nil and why not.
local function plan_for(instance, prepared)
  local standing = update_match.standing(instance)
  local shift = update_match.shift(instance, prepared, standing)
  local direction = instance.direction
  local position = shift and build_position(prepared, shift, direction)
  if not position then return nil, REASON.misaligned end
  local plan = {
    prepared = prepared, position = position, direction = direction, shift = shift, superforce = true,
    footprint = placement.footprint(prepared, position, direction), standing = #standing,
  }
  plan.fresh, plan.dropped = update_match.diff(standing, plan)
  return plan
end

-- The copy's entities the new version no longer has go to the robots.
local function drop_removed(instance, dropped)
  local force = game.forces[instance.force_index]
  for _, s in ipairs(dropped) do
    if s.entity.valid then s.entity.order_deconstruction(force) end
    instance.entities[s.unit] = nil
  end
end

-- Files what the superforced build returned: new ghosts join the copy.
local function adopt(instance, built)
  local slots, count = {}, 0
  for _, ghost in pairs(built or {}) do
    if ghost.valid and ghosts.is_marker(ghost) then
      ghost.destroy()
    elseif ghost.valid and ghost.type == "tile-ghost" then
      local p = ghost.position
      local key = geometry.tile_key(p.x, p.y)
      local was = instance.tiles[key]
      if not was then instance.tile_count = instance.tile_count + 1 end
      instance.tiles[key] = water.top_tile(was, ghost.ghost_name)
      instance.tile_units[ghost.unit_number] = true
      ghosts.watch(ghost, instance.id)
    elseif ghost.valid and ghost.type == "entity-ghost" then
      ghosts.tag(ghost, instance.id)
      ghosts.watch(ghost, instance.id)
      slots[geometry.position_key(ghost.position)] = ghost.ghost_name
      count = count + 1
    end
  end
  return slots, count
end

local function refuse(reason)
  return false, reason
end

-- How the copy's project treats it once the update is built:
--   "complete"  its sockets are open already: nothing to settle
--   "reopen"    it never opened them (it came out incomplete, or it waits
--               for its ore): it opens them as a copy just finished does
--   nil         it is still being built: it settles as it would have
local function settle_mode(instance)
  if instance.state == STATE.incomplete then return "reopen" end
  if instance.state ~= STATE.complete then return nil end
  local project = instance.project_id and storage.projects[instance.project_id]
  if project and project.waiting_ore and project.waiting_ore[instance.id] then
    project.waiting_ore[instance.id] = nil
    return "reopen"
  end
  return "complete"
end

-- The copy's record follows the new version.
local function refit(instance, design, plan)
  local prepared, position, direction = design.prepared, plan.position, plan.direction
  footprints.remove(instance)
  instance.position, instance.footprint, instance.version = position, plan.footprint, design.version
  -- The version it is built from: what looks under a copy's parts reads it
  -- (a shared reference, saved once).
  instance.origin, instance.prepared = plan.shift, prepared
  instance.sockets = placement.sockets(prepared, position, direction)
  instance.repeat_size = placement.repeat_size(prepared, direction)
  instance.expected = prepared.entity_count
  local sensors = {}
  for i, area in ipairs(prepared.sensors or {}) do sensors[i] = placement.area(prepared, area, position, direction) end
  instance.sensors, instance.sensor_categories = sensors, prepared.sensor_categories
  instance.port = prepared.port and placement.world(prepared, prepared.port, position, direction)
  footprints.add(instance)
end

-- Builds the new version over the copy and files what came of it.
local function rebuild(surface, instance, design, plan)
  local mode = settle_mode(instance)
  depletion.forget(instance)
  ghosts.each(surface, instance, function(ghost) ghost.destroy() end)
  drop_removed(instance, plan.dropped)
  local built = library.stamp_stack(design).build_blueprint {
    surface = surface, force = instance.force_index, position = plan.position, direction = plan.direction,
    build_mode = defines.build_mode.superforced, raise_built = true,
  }
  refit(instance, design, plan)
  clearance.clear(surface, game.forces[instance.force_index], plan.checked)
  local slots, count = adopt(instance, built)
  instance.slots, instance.updating, instance.ghosts_left = slots, mode, count
  instances.set_state(instance, STATE.building)
  instances.restart_deadline(instance)
  tracking.mark_dirty(instance)
end

-- The oldest version among a project's copies, for its row's update button.
function update.recount_project(project)
  local oldest
  for id in pairs(project.instance_ids) do
    local other = storage.instances[id]
    if other and other.state ~= STATE.retired then oldest = math.min(oldest or other.version, other.version) end
  end
  project.oldest_version = oldest
end

-- Microseconds a part costs that is new over the copy, measured on 2.1
-- headless with 4,998 chests laid over a copy's lamps: looked under 12,
-- checked where the copy's own entity stands 14, stamped and filed 7.5, the
-- old entity dropped 1.3. An electric pole's ghost also wires itself to
-- the poles in reach (budget.COST.pole).
local FRESH_PART = 40
local FRESH_POLE = FRESH_PART + COST.pole

-- Whether a prototype is an electric pole, by name: constant for the
-- session (prototypes cannot change while the script runs; rebuilt on
-- every load).
local poles = {}

local function is_pole(name)
  local known = poles[name]
  if known == nil then
    local proto = prototypes.entity[name]
    known = proto ~= nil and proto.type == "electric-pole"
    poles[name] = known
  end
  return known
end

local function area_of(box)
  local size = geometry.box_size(box)
  return size.x * size.y
end

-- What one update costs its force (budget.lua), an upper bound whether it
-- is refused or built: the fixed part; each entity of the copy and each
-- part of the new version read, matched and pasted over (measured at most
-- 6 each); each fresh part; the new footprint's chunks, walked twice (the
-- overlap index, the terrain); and, for a copy stamped before copies
-- recorded where their parts are, each tile of its footprint, which its
-- ghosts are looked for over (under.instance_boxes). `plan` is nil when no
-- shift was found.
function update.cost(instance, prepared, plan)
  local weighed = (plan and plan.standing or table_size(instance.entities)) + (prepared.parts or 0)
  local cost = COST.update_copy + weighed * (COST.check_part + COST.stamp_part)
  for _, e in ipairs(plan and plan.fresh or {}) do cost = cost + (is_pole(e.name) and FRESH_POLE or FRESH_PART) end
  if plan then cost = cost + 2 * spots.chunks(plan.footprint) * COST.chunk end
  if under.knows_parts(instance) then return cost end
  return cost + area_of(instance.footprint) * COST.area_tile
end

-- Moves the copy to the design's current version. Returns true, or false
-- and why not ("up-to-date", or a refusal reason). A caller that updates
-- many copies passes `batch` and recounts their projects once at the end
-- (update.recount_project): a recount per copy walks every copy again.
function update.run(instance, batch)
  local design = library.get(instance.force_index, instance.design_id)
  if not design or instance.state == STATE.retiring or instance.state == STATE.retired then
    return refuse(REASON.unknown_design)
  end
  if design.version == instance.version then return refuse("up-to-date") end
  local prepared = design.prepared
  if not (prepared and prepared.ok) then return refuse(REASON.invalid_design) end
  local surface = game.surfaces[instance.surface_index]
  local plan, why = plan_for(instance, prepared)
  if plan then why, plan.checked = update_fit.refusal(surface, instance, plan) end
  budget.charge(instance.force_index, update.cost(instance, prepared, plan))
  if why then return refuse(why) end
  rebuild(surface, instance, design, plan)
  local project = not batch and instance.project_id and storage.projects[instance.project_id]
  if project then update.recount_project(project) end
  return true
end

-- Whether a copy is behind its design's current version.
function update.outdated(instance)
  local design = library.get(instance.force_index, instance.design_id)
  return design ~= nil and instance.version < design.version
    and instance.state ~= STATE.retiring and instance.state ~= STATE.retired
end

return update
