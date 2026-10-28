-- Completion tracking. Events are hints, recounts are the truth:
--   a built event carrying our tag attaches the entity to its instance;
--   a registered ghost, tile ghost or item request vanishing marks the
--   instance dirty; once things go quiet a recount searches under its parts
--   and tiles for what is left (under.lua; a copy stamped before it kept
--   its parts searches its footprint). Counts are recomputed, never
--   decremented.

local const = require("scripts.const")
local geometry = require("scripts.core.geometry")
local scheduler = require("scripts.core.scheduler")
local footprints = require("scripts.core.footprints")
local instances = require("scripts.core.instances")
local ghosts = require("scripts.core.ghosts")
local under = require("scripts.core.under")
local blueprint_markers = require("scripts.core.blueprint_markers")

local tracking = {}

local STATE = const.STATE

local tile_key = geometry.tile_key

-- Where tracked entities were mined this tick for an upgrade or a
-- fast-replace ("surface:position" -> instance id). Their replacements are
-- built in the same tick, untagged. Nothing here outlives the tick, so it
-- needs no storage and every peer agrees on it.
local replaced = { tick = -1, at = {} }

function tracking.mark_dirty(instance)
  local now = game.tick
  instance.first_dirty_tick = instance.first_dirty_tick or now
  local due = math.min(now + const.QUIET_TICKS, instance.first_dirty_tick + const.MAX_RECOUNT_WAIT)
  instance.recount_tick = math.max(due, now + 1)
  if instance.recount_queued then return end
  instance.recount_queued = true
  scheduler.at(instance.recount_tick, { kind = "recount", id = instance.id })
end

-- Every ghost counted is watched, so that one never registered (a death
-- ghost from an older save, one restored by undo) still ends in a recount.
local function count_ghosts(surface, instance)
  local n = 0
  ghosts.each(surface, instance, function(ghost)
    n = n + 1
    ghosts.watch(ghost, instance.id)
  end)
  return n
end

-- Tile removal orders have no unit number; they are matched by position.
local function count_tile_proxies(surface, instance)
  if instance.tile_count == 0 then return 0 end
  local n = 0
  under.each(surface, nil, under.tile_boxes(instance.tiles), { type = "deconstructible-tile-proxy" }, function(proxy)
    local p = proxy.position
    if instance.tiles[tile_key(p.x, p.y)] then n = n + 1 end
  end)
  return n
end

-- Item requests still pending on the instance's built entities; each one is
-- watched so its delivery triggers the next recount.
local function count_requests(surface, instance)
  local n = 0
  local filter = { type = "item-request-proxy", force = instance.force_index }
  under.each(surface, nil, under.instance_boxes(instance), filter, function(proxy)
    local target = proxy.proxy_target
    if target and target.valid and target.unit_number and instance.entities[target.unit_number] then
      n = n + 1
      ghosts.watch(proxy, instance.id)
    end
  end)
  return n
end

-- Its item request already exists, and nothing else announces the delivery:
-- watching it makes the delivery trigger a recount.
local function attach(instance, entity)
  instance.entities[entity.unit_number] = entity
  storage.entity_regs[script.register_on_object_destroyed(entity)] = instance.id
  local proxy = entity.item_request_proxy
  if proxy then ghosts.watch(proxy, instance.id) end
end

-- The stamped slots no tracked entity fills, by position key, and the names
-- to search for. A name whose prototype is gone (a removed or renamed mod)
-- cannot be searched for.
local function open_slots(instance)
  local filled, open, names, seen = {}, {}, {}, {}
  for _, entity in pairs(instance.entities) do
    if entity.valid then filled[geometry.position_key(entity.position)] = true end
  end
  for key, name in pairs(instance.slots) do
    if not filled[key] and prototypes.entity[name] then
      open[key] = name
      if not seen[name] then names[#names + 1], seen[name] = name, true end
    end
  end
  return open, names
end

-- Entities that came up without a built event (a script revive without
-- raise_revive): once no ghost is left but entities are missing, adopt
-- untracked ones standing exactly where a ghost of that name stood. A
-- player's own entity elsewhere in the footprint is never taken.
local function adopt_unannounced(surface, instance)
  local open, names = open_slots(instance)
  if #names == 0 then return end
  local filter = { force = instance.force_index, name = names }
  under.each(surface, nil, under.instance_boxes(instance), filter, function(entity)
    local unit, key = entity.unit_number, geometry.position_key(entity.position)
    if unit and open[key] == entity.name and not instance.entities[unit] then
      open[key] = nil
      attach(instance, entity)
    end
  end)
end

-- Nothing of the copy stands or waits to be built: its parts were removed
-- by hand, say, or by another mod. Not a copy that placed no entity (tiles
-- only), one being updated, or one already gone.
local function emptied(instance, left)
  return left == 0 and (instance.expected or 0) > 0 and not instance.updating
    and instance.state ~= STATE.retired and instances.built_entities(instance) == 0
end

function tracking.recount(instance)
  local surface = game.surfaces[instance.surface_index]
  if not surface then return end
  if instance.state == STATE.retiring then
    return instances.counted(instance, count_tile_proxies(surface, instance))
  end
  local left = count_ghosts(surface, instance)
  if left == 0 and instances.is_building(instance) and instances.built_entities(instance) < instance.expected then
    adopt_unannounced(surface, instance)
  end
  left = left + count_requests(surface, instance)
  if emptied(instance, left) then return instances.release(instance) end
  instances.counted(instance, left)
end

scheduler.register("recount", function(item, now)
  local instance = storage.instances[item.id]
  if not instance then return end
  if instance.recount_tick and instance.recount_tick > now then
    return scheduler.at(instance.recount_tick, item)
  end
  instance.recount_queued, instance.recount_tick, instance.first_dirty_tick = nil, nil, nil
  tracking.recount(instance)
end)

local function position_of(entity)
  return entity.surface_index .. ":" .. geometry.position_key(entity.position)
end

-- The instance whose entity this one replaced in this tick, if any.
local function replacement_of(entity, tick)
  if replaced.tick ~= tick or not entity.valid then return nil end
  return replaced.at[position_of(entity)]
end

-- A blueprint taken over in-flight ghosts copies their tags, so a tag alone
-- proves nothing: the entity must stand in the footprint, for the force.
local function owns(instance, entity)
  return entity.surface_index == instance.surface_index and entity.force_index == instance.force_index
    and geometry.contains_point(instance.footprint, entity.position)
end

-- on_built_entity, on_robot_built_entity, script_raised_revive and
-- on_space_platform_built_entity all hand back the ghost's tags.
function tracking.on_built(event)
  local entity = event.entity
  local id = event.tags and event.tags[const.TAG] or replacement_of(entity, event.tick)
  if not (id and entity.valid and entity.unit_number) then return end
  local instance = storage.instances[id]
  if not (instance and owns(instance, entity)) or instance.state == STATE.retired then return end
  if instance.state == STATE.retiring then entity.order_deconstruction(entity.force) end
  attach(instance, entity)
  instances.progress(instance, event.tick)
  if instances.is_building(instance) then tracking.mark_dirty(instance) end
end

-- An upgrade or a fast-replace mines a tracked entity, then builds its
-- replacement untagged at the same position in the same tick: remember where
-- the tracked one stood. Robots also mine for plain deconstruction, so for
-- them only an entity marked for upgrade counts.
function tracking.on_mined(event)
  local entity = event.entity
  if not (entity.valid and entity.unit_number) then return end
  if event.robot and not entity.to_be_upgraded() then return end
  for _, id in ipairs(footprints.at(entity.surface_index, entity.position)) do
    local instance = storage.instances[id]
    if instance and instance.entities[entity.unit_number] then
      if replaced.tick ~= event.tick then replaced.tick, replaced.at = event.tick, {} end
      replaced.at[position_of(entity)] = id
      return
    end
  end
end

function tracking.on_object_destroyed(event)
  local reg = event.registration_number
  local id = storage.ghost_regs[reg]
  if id then
    storage.ghost_regs[reg] = nil
    local instance = storage.instances[id]
    if instance and (instances.is_building(instance) or instance.state == STATE.retiring) then
      tracking.mark_dirty(instance)
    end
    return
  end
  id = storage.entity_regs[reg]
  if not id then return end
  storage.entity_regs[reg] = nil
  local instance = storage.instances[id]
  if not instance then return end
  instances.entity_gone(instance, event.useful_id)
  -- A copy losing a part it was not asked to remove may have nothing left:
  -- its recount says, and releases it (instances.release).
  if instance.state ~= STATE.retiring and instance.state ~= STATE.retired then tracking.mark_dirty(instance) end
end

-- An entity of ours died and left a ghost: tag the ghost so the rebuilt
-- entity is ours again, and watch it so its removal ends in a recount.
function tracking.on_post_entity_died(event)
  local ghost, unit = event.ghost, event.unit_number
  if not (ghost and ghost.valid and unit) then return end
  for _, id in ipairs(footprints.at(event.surface_index, event.position)) do
    local instance = storage.instances[id]
    if instance and instance.entities[unit] ~= nil then
      ghosts.tag(ghost, id)
      ghosts.watch(ghost, id)
      return
    end
  end
end

local function blueprint_set_up(event)
  local record = event.record
  if record and record.valid and record.type == "blueprint" then return record end
  local stack = event.stack
  if stack and stack.valid_for_read and stack.is_blueprint then return stack end
end

-- A blueprint taken over in-flight stamps captures their ghosts' tags; strip
-- them, so a library copy never carries one instance's id around. The
-- copies it covers get their markers back (blueprint_markers.lua).
function tracking.on_player_setup_blueprint(event)
  local blueprint = blueprint_set_up(event)
  if not (blueprint and blueprint.is_blueprint_setup()) then return end
  for i = 1, blueprint.get_blueprint_entity_count() do
    if blueprint.get_blueprint_entity_tag(i, const.TAG) ~= nil then blueprint.set_blueprint_entity_tag(i, const.TAG, nil) end
  end
  blueprint_markers.add(event, blueprint)
end

return tracking
