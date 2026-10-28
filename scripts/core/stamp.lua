-- All-or-nothing stamping. After the footprint checks pass, the design's
-- stamping copy is built in forced mode; every entity ghost is tagged with
-- its instance and registered, tile ghosts are recorded, and marker ghosts
-- are read and destroyed in the same tick. A stamp that still comes out
-- short, or whose entry arrow lands anywhere but its target, is rolled back
-- whole.

local const = require("scripts.const")
local geometry = require("scripts.core.geometry")
local registry = require("scripts.core.registry")
local library = require("scripts.core.library")
local placement = require("scripts.core.placement")
local instances = require("scripts.core.instances")
local tracking = require("scripts.core.tracking")
local ghosts = require("scripts.core.ghosts")
local clearing = require("scripts.core.clearing")
local clearance = require("scripts.core.clearance")
local water = require("scripts.core.water")

local stamp = {}

-- True while our own build_blueprint runs: its script_raised_built events
-- are ours to ignore (marker ghosts are read after the call returns).
local building = false

-- The entry ghost must sit on the plan's target, facing its direction.
local function entry_lands(plan, ghost)
  local target = plan.entry_target
  if not target then return true end
  local want = geometry.turn(plan.prepared.entry.direction, plan.direction)
  local p = ghost.position
  return math.abs(p.x - target.x) < 0.01 and math.abs(p.y - target.y) < 0.01 and ghost.direction == want
end

local function keep_entity(record, ghost, id)
  ghosts.tag(ghost, id)
  record.entities = record.entities + 1
  record.slots[geometry.position_key(ghost.position)] = ghost.ghost_name
  record.ghosts[#record.ghosts + 1] = ghost
  record.regs[#record.regs + 1] = ghosts.watch(ghost, id)
end

-- A tile is counted once, though the engine may stack its landfill ghost
-- under a design tile's on water (water.lua).
local function keep_tile(record, ghost, id)
  local p = ghost.position
  local key = geometry.tile_key(p.x, p.y)
  local was = record.tiles[key]
  if not was then record.tile_count = record.tile_count + 1 end
  record.tiles[key] = water.top_tile(was, ghost.ghost_name)
  record.tile_units[ghost.unit_number] = true
  record.ghosts[#record.ghosts + 1] = ghost
  record.regs[#record.regs + 1] = ghosts.watch(ghost, id)
end

-- Sorts what build_blueprint returned (walked with pairs: a handler may
-- have left holes). Marker ghosts are checked and destroyed here.
local function collect(built, id, plan)
  local record = {
    ghosts = {}, regs = {}, entities = 0, slots = {}, tiles = {}, tile_units = {}, tile_count = 0, aligned = true,
  }
  for _, ghost in pairs(built) do
    if ghost and ghost.valid then
      if ghost.type == "tile-ghost" then
        keep_tile(record, ghost, id)
      elseif ghosts.is_marker(ghost) then
        if ghost.ghost_name == const.ENTRY and not entry_lands(plan, ghost) then record.aligned = false end
        ghost.destroy()
      elseif ghosts.is_foreign_marker(ghost) then
        ghost.destroy()
      elseif ghost.type == "entity-ghost" then
        keep_entity(record, ghost, id)
      end
    end
  end
  return record
end

local function rollback(record)
  for _, reg in ipairs(record.regs) do storage.ghost_regs[reg] = nil end
  for _, ghost in ipairs(record.ghosts) do
    if ghost.valid then ghost.destroy() end
  end
end

local function build(plan, ctx)
  building = true
  local ok, built = pcall(library.stamp_stack(plan.design).build_blueprint, {
    surface = ctx.surface, force = ctx.force, position = plan.position, direction = plan.direction,
    build_mode = plan.superforce and defines.build_mode.superforced or defines.build_mode.forced, raise_built = true,
  })
  building = false
  if not ok then
    log("[self-expanding-blueprints] build_blueprint failed: " .. tostring(built))
    return nil
  end
  return built
end

local function verdict(record, plan)
  if not record.aligned then return const.REASON.misaligned end
  if record.entities < plan.prepared.entity_count then return const.REASON.stamp_short end
end

-- The areas the design's ore sensors watch, in world space.
local function sensor_areas(plan)
  local list = {}
  for i, area in ipairs(plan.prepared.sensors or {}) do
    list[i] = placement.area(plan.prepared, area, plan.position, plan.direction)
  end
  return list
end

-- plan: design, prepared, position, direction, footprint, entry_target, and
-- what checks.obstacles noted (cliffs to blow up).
-- ctx: surface, force, project_id, parent, socket.
-- Returns the new instance, or nil and a reason.
function stamp.run(plan, ctx)
  local id = registry.new_instance_id()
  -- A forced paste marks trees, rocks and cliffs it may clear for removal, a
  -- superforced one the force's buildings too: a stamp that is rolled back
  -- takes those back.
  local unmarked = clearing.unmarked(ctx.surface, ctx.force, plan, plan.superforce)
  local built = build(plan, ctx)
  if not built then
    clearing.take_back(unmarked, ctx.force)
    return nil, const.REASON.stamp_short
  end
  local record = collect(built, id, plan)
  local refused = verdict(record, plan)
  if refused then
    rollback(record)
    clearing.take_back(unmarked, ctx.force)
    return nil, refused
  end
  clearance.clear(ctx.surface, ctx.force, plan)
  local instance = {
    id = id, design_id = plan.design.id, version = plan.design.version,
    force_index = ctx.force.index, surface_index = ctx.surface.index, project_id = ctx.project_id,
    position = plan.position, direction = plan.direction, footprint = plan.footprint,
    -- The version's prepared data, shared with the design (a save keeps it
    -- once): where the copy's parts are, so a recount looks under them.
    prepared = plan.prepared,
    origin = placement.world(plan.prepared, { x = 0, y = 0 }, plan.position, plan.direction),
    repeat_size = placement.repeat_size(plan.prepared, plan.direction),
    parent = ctx.parent, socket_index = ctx.socket,
    sockets = placement.sockets(plan.prepared, plan.position, plan.direction),
    sensors = sensor_areas(plan), sensor_categories = plan.prepared.sensor_categories,
    port = plan.prepared.port and placement.world(plan.prepared, plan.prepared.port, plan.position, plan.direction),
    entities = {}, expected = record.entities, slots = record.slots,
    tiles = record.tiles, tile_units = record.tile_units, tile_count = record.tile_count,
    ghosts_left = #record.ghosts,
  }
  instances.add(instance)
  -- The first recount also settles a stamp that needed nothing built.
  tracking.mark_dirty(instance)
  return instance
end

-- Marker ghosts built by anyone else's script (another mod stamping one of
-- our designs) could never be built by robots; remove them on sight.
function stamp.on_script_raised_built(event)
  if building then return end
  local entity = event.entity
  if entity and entity.valid and ghosts.is_marker(entity) then
    entity.destroy()
  end
end

return stamp
