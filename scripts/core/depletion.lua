-- Depletion: copies that wait for their ore to run out, and copies that are
-- removed once it has (DESIGN.md, "Depletion").
--   A finished copy of a design with ore sensors opens its sockets only when
--   no ore is left in any area its sensors watch.
--   With the project option retire_depleted, a finished copy whose mining
--   drills have nothing left to mine retires after its output has drained.
-- Both wake on on_resource_depleted: an index of watched areas by chunk says
-- which copies to look at again, a little later, by counting what is left
-- (resources.lua). A copy has at most one look of each kind queued: a run of
-- depleted tiles under it is one look, not one per tile.

local scheduler = require("scripts.core.scheduler")
local geometry = require("scripts.core.geometry")
local resources = require("scripts.core.resources")
local const = require("scripts.const")

local depletion = {}

-- ore_gone(instance): its sensors see no ore left. dry(instance): its
-- drills have nothing left to mine. Set by projects.lua.
depletion.hooks = {}

local KIND = { ore = "ore", drills = "drills" }

-- storage.watches[kind][surface_index][chunk_key] = {[instance_id] = true}
local function index(kind, surface_index)
  storage.watches = storage.watches or {}
  local by_kind = storage.watches[kind] or {}
  storage.watches[kind] = by_kind
  local by_surface = by_kind[surface_index] or {}
  by_kind[surface_index] = by_surface
  return by_surface
end

local function watch(kind, instance, boxes)
  local buckets = index(kind, instance.surface_index)
  for _, box in ipairs(boxes) do
    geometry.each_chunk(box, function(cx, cy)
      local key = geometry.chunk_key(cx, cy)
      local bucket = buckets[key] or {}
      buckets[key] = bucket
      bucket[instance.id] = true
    end)
  end
end

local function unwatch(kind, instance, boxes)
  local buckets = index(kind, instance.surface_index)
  for _, box in ipairs(boxes) do
    geometry.each_chunk(box, function(cx, cy)
      local key = geometry.chunk_key(cx, cy)
      local bucket = buckets[key]
      if bucket then
        bucket[instance.id] = nil
        if next(bucket) == nil then buckets[key] = nil end
      end
    end)
  end
end

-- Ore that can run out (an infinite resource never does) and that the
-- sensor's drill could mine, when the sensor sits on a drill, in any area a
-- copy's sensors watch.
local function ore_left(instance)
  local surface = game.surfaces[instance.surface_index]
  if not surface then return false end
  local categories = instance.sensor_categories or {}
  for i, box in ipairs(instance.sensors) do
    if resources.left(surface, box, categories[i], false) then return true end
  end
  return false
end

-- A finished copy: true when its sockets may open now. A copy whose sensors
-- still see ore waits, watched, and opens through hooks.ore_gone.
function depletion.ready(instance)
  if not (instance.sensors and #instance.sensors > 0) then return true end
  if not ore_left(instance) then return true end
  instance.waiting_ore = true
  watch(KIND.ore, instance, instance.sensors)
  return false
end

-- The mining area of each of a copy's drills, with the drill: the built
-- entity's own, which a better quality makes larger.
local function drills_of(instance)
  local list = {}
  for _, entity in pairs(instance.entities) do
    if entity.valid and entity.type == "mining-drill" then
      list[#list + 1] = { drill = entity, box = geometry.from_area(entity.mining_area) }
    end
  end
  return list
end

local function boxes(list)
  local out = {}
  for i, d in ipairs(list) do out[i] = d.box end
  return out
end

-- Something a drill could still mine in its area: an infinite resource
-- counts, a pumpjack over oil is never dry.
local function minable(drill, box)
  return resources.left(drill.surface, box, drill.prototype.resource_categories or {}, true)
end

-- Every drill it has has nothing to mine. A copy missing a drill (destroyed,
-- not yet rebuilt) is not dry: that one may stand over ore.
local function dry(instance)
  local list = drills_of(instance)
  if #list == 0 or #list < (instance.drill_count or 0) then return false end
  for _, d in ipairs(list) do
    if minable(d.drill, d.box) then return false end
  end
  return true
end

-- Whether the copy is going for depletion: it is being removed for it, or
-- it will be once its drills run dry, its project removing mined-out copies
-- (its drills are watched), and they have, or its sensors see no ore left
-- (its sockets are open, so they do). A child that only it stands in the
-- way of waits for it to go (growth.lua).
function depletion.going(instance)
  if instance.state == const.STATE.retiring then return instance.retired_for == "depleted" end
  if not (instance.drill_areas and instance.state == const.STATE.complete) then return false end
  return (#(instance.sensors or {}) > 0 and not instance.waiting_ore) or dry(instance)
end

-- The same of a design's copies, for a plan, which mines nothing and opens
-- a copy's sockets at once: a copy with drills and sensors would be going,
-- in a project that removes mined-out copies, by the time they open.
function depletion.mined_out_goes(prepared)
  return (prepared.drill_count or 0) > 0 and #(prepared.sensors or {}) > 0
end

-- The tick a copy's queued look of each kind is due (kept on the copy).
local QUEUED = { ["ore-check"] = "ore_check_tick", ["drill-check"] = "drill_check_tick" }

-- Queues a look unless one of its kind is queued already: a depleted
-- resource is removed right after its event, so every one that asks for a
-- look before the queued one is made is gone by then, and that look sees all.
local function check_later(kind, instance, delay)
  local field = QUEUED[kind]
  if instance[field] then return end
  instance[field] = game.tick + delay
  scheduler.at(instance[field], { kind = kind, id = instance.id })
end

-- A finished copy of a project that retires depleted copies: watch where
-- its drills mine. A copy without drills is never watched; one whose drills
-- are dry already (mined out while it was being finished) goes after the
-- usual drain. The copy keeps the mark, so it still goes once its finished
-- project is forgotten (copy_events.lua).
function depletion.watch_drills(instance)
  instance.retire_depleted = true
  local list = drills_of(instance)
  if #list == 0 then return end
  instance.drill_areas, instance.drill_count = boxes(list), #list
  watch(KIND.drills, instance, instance.drill_areas)
  if dry(instance) then check_later("drill-check", instance, const.DRAIN_TICKS) end
end

-- Drops what a copy waits for at the ore, and only that: a forgotten
-- finished project's copies keep their drills watched.
function depletion.forget_ore(instance)
  if instance.waiting_ore then unwatch(KIND.ore, instance, instance.sensors) end
  instance.waiting_ore = nil
end

-- Drops whatever a copy is watched for (it retired, its record is gone, or
-- an update in place watches it again once it is built).
function depletion.forget(instance)
  depletion.forget_ore(instance)
  if instance.drill_areas then unwatch(KIND.drills, instance, instance.drill_areas) end
  instance.drill_areas = nil
end

-- Its project stopped: nothing it asked for at the ore happens any more,
-- and the copy loses the mark that it goes when its drills run dry.
function depletion.let_go(instance)
  depletion.forget(instance)
  instance.retire_depleted = nil
end

-- A queued look: the copy may be asked again from now on, then `look` runs.
local function on_look(kind, look)
  scheduler.register(kind, function(item)
    local instance = storage.instances[item.id]
    if not instance then return end
    instance[QUEUED[kind]] = nil
    look(instance)
  end)
end

-- Its sensors see no ore left: its sockets open.
local function ore_gone(instance)
  unwatch(KIND.ore, instance, instance.sensors)
  instance.waiting_ore = nil
  if depletion.hooks.ore_gone then depletion.hooks.ore_gone(instance) end
end

on_look("ore-check", function(instance)
  if not instance.waiting_ore or ore_left(instance) then return end
  ore_gone(instance)
end)

-- A copy found dry may have seen its last ore go less than an ore look ago:
-- that look would find the copy forgotten and never open its sockets, so
-- they open here, before it retires.
on_look("drill-check", function(instance)
  if not (instance.drill_areas and instance.state == const.STATE.complete) or not dry(instance) then return end
  if instance.waiting_ore and not ore_left(instance) then ore_gone(instance) end
  depletion.forget(instance)
  if depletion.hooks.dry then depletion.hooks.dry(instance) end
end)

-- The copies watching this position, looked at again a little later (the
-- depleted resource is removed right after this event).
local function wake(kind, check, surface_index, position, delay)
  local buckets = index(kind, surface_index)
  local key = geometry.chunk_key(math.floor(position.x / geometry.CHUNK), math.floor(position.y / geometry.CHUNK))
  for id in pairs(buckets[key] or {}) do
    local instance = storage.instances[id]
    local list = instance and (kind == KIND.ore and instance.sensors or instance.drill_areas)
    for _, box in ipairs(list or {}) do
      if geometry.contains_point(box, position) then
        check_later(check, instance, delay)
        break
      end
    end
  end
end

function depletion.on_resource_depleted(event)
  local resource = event.entity
  if not (resource and resource.valid) then return end
  local surface_index, position = resource.surface_index, resource.position
  wake(KIND.ore, "ore-check", surface_index, position, const.ORE_CHECK_DELAY)
  wake(KIND.drills, "drill-check", surface_index, position, const.DRAIN_TICKS)
end

return depletion
