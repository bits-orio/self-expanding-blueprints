-- Instance lifecycle. Every stamp is an instance that remembers its own
-- entities, so completion, exact retirement and (later) updates follow from
-- the record. Completion is decided by recounts (tracking.lua), never by a
-- decrementing counter. A retired instance's record is forgotten once its
-- event is out and nothing grows from it (forgetting.lua).

local const = require("scripts.const")
local geometry = require("scripts.core.geometry")
local scheduler = require("scripts.core.scheduler")
local footprints = require("scripts.core.footprints")
local ghosts = require("scripts.core.ghosts")
local gates = require("scripts.core.gates")
local forgetting = require("scripts.core.forgetting")
local overlay = require("scripts.render.overlay")
local events = require("scripts.remote.events")

local instances = {}

local STATE = const.STATE
local REASON = const.REASON

-- Set by projects.lua: completed(instance), incomplete(instance). An instance
-- that stops building without completing (incomplete, or retired early)
-- reports incomplete so its project releases the slot. state(instance,
-- old_state) follows every state change made through set_state. updated and
-- reopened(instance) end an update in place (update.lua). retired(instance):
-- it is gone, its footprint out of the overlap index.
instances.hooks = {}

local function payload(instance)
  return {
    instance_id = instance.id, design_id = instance.design_id, version = instance.version,
    force_index = instance.force_index, surface_index = instance.surface_index, project_id = instance.project_id,
    reason = instance.reason,
  }
end

local function building(instance)
  return instance.state == STATE.building or instance.state == STATE.stalled
end
instances.is_building = building

function instances.set_state(instance, state, reason)
  local old_state = instance.state
  instance.state = state
  instance.reason = reason
  overlay.refresh_instance(instance)
  if instances.hooks.state then instances.hooks.state(instance, old_state) end
end

local function schedule_deadline(instance, tick)
  scheduler.at(tick, { kind = "deadline", id = instance.id })
end

-- Files a freshly stamped instance (its id, ghosts and footprint are set).
function instances.add(instance)
  instance.state = STATE.building
  instance.children = instance.children or {}
  instance.created_tick = game.tick
  instance.last_progress_tick = game.tick
  storage.instances[instance.id] = instance
  footprints.add(instance)
  local parent = instance.parent and storage.instances[instance.parent]
  if parent then parent.children[#parent.children + 1] = instance.id end
  schedule_deadline(instance, game.tick + const.STALL_TICKS)
  overlay.refresh_instance(instance)
end

-- An update puts a finished copy back to building: its stall clock starts
-- again from now.
function instances.restart_deadline(instance)
  instance.last_progress_tick = game.tick
  schedule_deadline(instance, game.tick + const.STALL_TICKS)
end

function instances.progress(instance, tick)
  instance.last_progress_tick = tick
  if instance.state == STATE.stalled then instances.set_state(instance, STATE.building) end
end

-- No item in the supply (a network, or a platform's hub) could place this
-- ghost.
local function lacks(supply, ghost)
  for _, item in pairs(ghost.ghost_prototype.items_to_place_this or {}) do
    if supply.get_item_count({ name = item.name, quality = ghost.quality.name }) > 0 then return false end
  end
  return true
end

-- Why it is not being finished: nothing builds there (no network covers
-- it), or the supply has nothing that could place one of its ghosts; else
-- plain lack of progress.
local function stall_reason(instance)
  local surface, force = game.surfaces[instance.surface_index], game.forces[instance.force_index]
  if not (surface and force) then return REASON.no_progress end
  local supply = gates.supply_at(surface, force, geometry.box_center(instance.footprint))
  if not supply then return REASON.no_network end
  local short = false
  ghosts.each(surface, instance, function(ghost) short = short or lacks(supply, ghost) end)
  return short and REASON.missing_materials or REASON.no_progress
end

scheduler.register("deadline", function(item, now)
  local instance = storage.instances[item.id]
  if not (instance and building(instance)) then return end
  local quiet_until = instance.last_progress_tick + const.STALL_TICKS
  if now < quiet_until then return schedule_deadline(instance, quiet_until) end
  local reason = stall_reason(instance)
  if instance.state ~= STATE.stalled or instance.reason ~= reason then
    local was_stalled = instance.state == STATE.stalled
    instances.set_state(instance, STATE.stalled, reason)
    if not was_stalled then script.raise_event(events.on_instance_stalled, payload(instance)) end
  end
  schedule_deadline(instance, now + const.STALL_TICKS)
end)

local function built_entities(instance)
  local n = 0
  for unit, entity in pairs(instance.entities) do
    if entity.valid then n = n + 1 else instance.entities[unit] = nil end
  end
  return n
end
instances.built_entities = built_entities

local function built_tiles(instance, surface)
  local n = 0
  for key, name in pairs(instance.tiles) do
    local x, y = geometry.tile_xy(key)
    if surface.get_tile(x, y).name == name then n = n + 1 end
  end
  return n
end

local function settle(instance, hook)
  if instances.hooks[hook] then instances.hooks[hook](instance) end
end

-- An updated copy (update.lua) finishes like any other, but its project
-- already counted it: "complete" settles nothing again, "reopen" opens its
-- sockets now (hooks.reopened), and a copy updated mid-build (no mode)
-- settles as it would have.
local function finish_building(instance)
  local surface = game.surfaces[instance.surface_index]
  local short = built_entities(instance) < instance.expected
    or (surface and built_tiles(instance, surface) < instance.tile_count)
  local updating = instance.updating
  instance.updating = nil
  if short then
    instance.slots = {}
    instances.set_state(instance, STATE.incomplete, REASON.ghost_removed)
    if updating then return end
    return settle(instance, "incomplete")
  end
  instance.tile_units, instance.slots = {}, {}   -- only needed while building
  instances.set_state(instance, STATE.complete)
  script.raise_event(events.on_instance_completed, payload(instance))
  if updating == "complete" then return settle(instance, "updated") end
  if updating == "reopen" then return settle(instance, "reopened") end
  -- A subscriber may retire it from that event: its project slot is freed
  -- either way, but its sockets open only if it is still complete.
  settle(instance, instance.state == STATE.complete and "completed" or "incomplete")
end

-- A recount's result: what is still to be built (ghosts, tile ghosts and
-- pending item requests) or, while retiring, still to be removed.
function instances.counted(instance, left)
  if instance.state == STATE.retiring then
    instance.ghosts_left = left
    return instances.check_retired(instance, left)
  end
  if not building(instance) then return end
  -- Laid tiles and delivered items raise no built event, but they are progress.
  if left < (instance.ghosts_left or math.huge) then instances.progress(instance, game.tick) end
  instance.ghosts_left = left
  if left > 0 then return overlay.refresh_instance(instance) end
  finish_building(instance)
end

function instances.entity_gone(instance, unit_number)
  instance.entities[unit_number] = nil
  if instance.state == STATE.retiring then instances.check_retired(instance, instance.tile_proxies_left or 0) end
end

local function finish_retire(instance)
  instance.state = STATE.retired
  instance.entities, instance.tiles, instance.tile_units, instance.sockets, instance.slots = {}, {}, {}, {}, {}
  forgetting.unindex(instance)
  script.raise_event(events.on_instance_retired, payload(instance))
  settle(instance, "retired")
  forgetting.after_retire(instance)
end

-- A copy with nothing of it left (tracking.lua) leaves as if retired and
-- removes nothing: its spot is free, and any tiles it laid stay (D55).
function instances.release(instance)
  local was_building = building(instance)
  instances.set_state(instance, STATE.retiring)
  if was_building then settle(instance, "incomplete") end
  finish_retire(instance)
end

-- Retired once no entity of it stands and no tile of it awaits removal.
function instances.check_retired(instance, tile_proxies_left)
  instance.tile_proxies_left = tile_proxies_left
  if built_entities(instance) > 0 or tile_proxies_left > 0 then return false end
  finish_retire(instance)
  return true
end

local function destroy(ghost)
  ghost.destroy()
end

local function order_entities(instance, force)
  for unit, entity in pairs(instance.entities) do
    if not entity.valid then
      instance.entities[unit] = nil
    elseif not entity.to_be_deconstructed() and not entity.order_deconstruction(force) then
      -- Not deconstructible by robots (e.g. not minable): stop tracking it,
      -- registration included, so nothing names this copy once it is forgotten.
      instance.entities[unit] = nil
      storage.entity_regs[script.register_on_object_destroyed(entity)] = nil
    end
  end
end

-- Orders our own tiles (only where the tile is still the one we placed);
-- returns how many await robots.
local function order_tiles(surface, instance, force)
  local pending = 0
  for key, name in pairs(instance.tiles) do
    local x, y = geometry.tile_xy(key)
    local current = surface.get_tile(x, y)
    if current.name == name then
      local proxy = current.order_deconstruction(force)
      if proxy then
        storage.ghost_regs[script.register_on_object_destroyed(proxy)] = instance.id
        pending = pending + 1
      end
    end
  end
  return pending
end

-- Removes exactly what this instance built. Returns false and a reason when
-- it is already retiring or retired.
function instances.retire(instance)
  if instance.state == STATE.retiring or instance.state == STATE.retired then return false, "already-retiring" end
  local was_building = building(instance)
  local surface, force = game.surfaces[instance.surface_index], game.forces[instance.force_index]
  local pending = 0
  if surface and force then
    ghosts.each(surface, instance, destroy)
    order_entities(instance, force)
    pending = order_tiles(surface, instance, force)
  end
  instances.set_state(instance, STATE.retiring)
  -- A copy being updated holds no slot of its project's: nothing to free.
  if was_building and not instance.updating then settle(instance, "incomplete") end
  instance.updating = nil
  instances.check_retired(instance, pending)
  return true
end

function instances.summary(instance)
  return {
    id = instance.id, design_id = instance.design_id, version = instance.version, state = instance.state,
    reason = instance.reason, ghosts_left = instance.ghosts_left, project_id = instance.project_id,
    surface_index = instance.surface_index, force_index = instance.force_index,
    position = instance.position, direction = instance.direction, footprint = instance.footprint,
    parent = instance.parent, children = instance.children, entity_count = built_entities(instance),
    sensors = instance.sensors, waiting_ore = instance.waiting_ore == true,
    created_tick = instance.created_tick, last_progress_tick = instance.last_progress_tick,
    ore_check_tick = instance.ore_check_tick, drill_check_tick = instance.drill_check_tick,
  }
end

-- The retired copies of a project, forgotten when the project ends (D45):
-- the ones kept because it grew from them (forgetting.lua).
instances.forget_retired_of = forgetting.retired_of

function instances.drop_where(predicate)
  for _, instance in pairs(storage.instances) do
    if predicate(instance) then
      forgetting.unindex(instance)
      forgetting.forget(instance)
    end
  end
end

return instances
