-- Prepared data for one design version, computed once when it is registered:
-- its markers (sockets, entry, the areas its ore sensors watch), footprint
-- bounds, snap grid (and its absolute offset, when the blueprint snaps
-- absolutely), bill of materials, placement lattice, and the calibrated
-- offsets of its stamping copy.
--
-- The stamping copy is the player's blueprint with snapping cleared (so the
-- build position is a plain offset) and one anchor entity added inside its
-- bounds (so calibration can always find it). Everything is read back from
-- the copy after editing it, because that copy is what gets stamped.
--
-- A design too big for the map's limits (D45) is refused before any of that:
-- wider or taller than const.MAX_DESIGN_SPAN, markers included, with more
-- parts (entities and tiles) than seb-max-design-parts allows, or with more
-- drawn sockets than const.MAX_DESIGN_SOCKETS. Only when it is registered (a
-- new design or version): one prepared again after a mod change keeps
-- working under a lowered cap.

local const = require("scripts.const")
local geometry = require("scripts.core.geometry")
local calibration = require("scripts.core.calibration")
local limits = require("scripts.core.limits")
local signals = require("scripts.core.signals")
local sensors = require("scripts.core.sensors")
local probes = require("scripts.core.probes")

local prepare = {}

-- `parts` is set when lab work was done for it, so the force pays for it.
local function fail(design, error, parts)
  return { ok = false, error = error, version = design.version, sockets = {}, parts = parts }
end

local function trim(text)
  return (text or ""):match("^%s*(.-)%s*$")
end

local function socket_target(entity)
  local name = trim(entity.player_description)
  if name == "" then return { kind = "self" } end
  return { kind = "named", name = name }
end

-- Sorts blueprint entities into sockets, entries, sensors, probes, the
-- anchor and the rest.
local function split(entities)
  local parts = { sockets = {}, entries = {}, sensors = {}, probes = {}, ports = {}, clears = {}, buildable = {} }
  for _, e in ipairs(entities) do
    local foreign = const.FOREIGN_MARKERS[e.name]
    if e.name == const.CLEAR or foreign == "clear" then
      parts.clears[#parts.clears + 1] = e.position
    elseif foreign then
      -- Another mod's marker this mod does not use: no part of the design.
    elseif e.name == const.SOCKET then
      parts.sockets[#parts.sockets + 1] = {
        position = e.position, direction = e.direction or 0, target = socket_target(e), number = signals.first_value(e),
      }
    elseif e.name == const.ENTRY then
      parts.entries[#parts.entries + 1] = { position = e.position, direction = e.direction or 0, number = signals.first_value(e) }
    elseif e.name == const.SENSOR then
      parts.sensors[#parts.sensors + 1] = { position = e.position, radius = signals.virtual(e, const.RADIUS_SIGNAL) }
    elseif e.name == const.PROBE then
      parts.probes[#parts.probes + 1] = probes.read(e)
    elseif e.name == const.PORT then
      parts.ports[#parts.ports + 1] = e.position
    elseif e.name == const.ANCHOR then
      parts.anchor = e.position
    else
      parts.buildable[#parts.buildable + 1] = { name = e.name, position = e.position, direction = e.direction or 0 }
    end
  end
  return parts
end

-- The whole tiles an entity covers, in blueprint coordinates: its tile
-- size, turned for east and west. The engine measures a blueprint the same
-- way (collision boxes do not reproduce its placement; spike S1).
local function entity_box(e)
  local proto = prototypes.entity[e.name]
  local w, h = proto and proto.tile_width or 1, proto and proto.tile_height or 1
  local direction = e.direction or defines.direction.north
  if direction == defines.direction.east or direction == defines.direction.west then
    w, h = h, w
  elseif not geometry.is_cardinal(direction) then
    w = math.max(w, h)
    h = w
  end
  local p = e.position
  return geometry.tile_box(geometry.box(p.x - w / 2, p.y - h / 2, p.x + w / 2, p.y + h / 2))
end

local function tile_box(t)
  return geometry.box(t.position.x, t.position.y, t.position.x + 1, t.position.y + 1)
end

-- The footprint: every part, every tile, and the Keep clear tiles, which
-- other copies must keep off too.
local function bounds_of(buildable, tiles, clears)
  local bounds
  for _, e in ipairs(buildable) do bounds = geometry.union(bounds, entity_box(e)) end
  for _, t in ipairs(tiles) do bounds = geometry.union(bounds, tile_box(t)) end
  for _, p in ipairs(clears) do
    local x, y = math.floor(p.x), math.floor(p.y)
    bounds = geometry.union(bounds, geometry.box(x, y, x + 1, y + 1))
  end
  return bounds
end

-- Everything a stamp of the blueprint covers: its parts and tiles (`inner`)
-- and every marker, ours or another mod's. The engine centres this box on
-- the build position (spike S1); its size is the design's span.
local function reach_of(inner, entities)
  local reach = inner
  for _, e in ipairs(entities) do
    if const.MARKERS[e.name] or const.FOREIGN_MARKERS[e.name] then reach = geometry.union(reach, entity_box(e)) end
  end
  return reach
end

-- Whether `count` parts are more than a design of the force may have.
function prepare.too_many_parts(count, force_index)
  local cap = limits.of(force_index, "design_parts")
  return cap > 0 and count > cap
end

-- The tiles a blueprint lays, from its bill of materials: one item of a
-- tile-laying kind each. The engine keeps it, so it costs 0.2 ms for 100,000
-- tiles, where listing them costs 60 ms and exporting them a second.
local function tile_items(source)
  local n = 0
  for _, item in ipairs(source.cost_to_build) do
    local proto = prototypes.item[item.name]
    if proto and proto.place_as_tile_result then n = n + item.count end
  end
  return n
end

-- A blueprint's parts (a stack or a library record), tiles included, told
-- from figures the engine keeps, or nil when they are more than `room`: its
-- tiles are priced only when its entities fit.
function prepare.parts_within(source, room)
  local entities = source.get_blueprint_entity_count()
  if entities > room then return nil end
  local parts = entities + tile_items(source)
  if parts <= room then return parts end
end

-- What a copy of a blueprint covers, in the blueprint's own coordinates: its
-- parts, tiles and Keep clear tiles; nil for an empty one.
function prepare.footprint_of(entities, tiles)
  local parts = split(entities)
  return bounds_of(parts.buildable, tiles, parts.clears)
end

-- Whether a blueprint has more parts than a design of the force may: asked
-- before it is exported or its lists are read.
function prepare.oversized(force_index, source)
  local cap = limits.of(force_index, "design_parts")
  return cap > 0 and prepare.parts_within(source, cap) == nil
end

-- The refusals of the size limits: a new design refused so is not kept.
prepare.LIMITS = {
  [const.REASON.design_too_big] = true, [const.REASON.too_many_sockets] = true, [const.REASON.too_many_poles] = true,
}

-- The parts of a design of one entity type: electric poles (a size limit),
-- mining drills (depletion.lua).
local function count_type(buildable, type)
  local n = 0
  for _, e in ipairs(buildable) do
    local proto = prototypes.entity[e.name]
    if proto and proto.type == type then n = n + 1 end
  end
  return n
end

local function too_wide(reach)
  return reach ~= nil and math.max(reach.right - reach.left, reach.bottom - reach.top) > const.MAX_DESIGN_SPAN
end

-- Plugs are told apart by their numbers: no two may share one (or both have
-- none).
local function plugs_apart(entries)
  local seen = {}
  for _, entry in ipairs(entries) do
    local key = entry.number or "none"
    if seen[key] then return false end
    seen[key] = true
  end
  return true
end

-- The plug a socket without a number uses: the one without a number, else
-- the lowest numbered.
local function main_plug(entries)
  local best
  for _, entry in ipairs(entries) do
    if not entry.number then return entry end
    if not best or entry.number < best.number then best = entry end
  end
  return best
end

-- What the blueprint holds, or why it cannot be a design. The size limits,
-- when `limited`, come first and read nothing but the blueprint's own lists
-- (its engine figures alone, when those are already over).
local function read(design, source, limited)
  local too_big, force_index = const.REASON.design_too_big, design.force_index
  if limited and prepare.oversized(force_index, source) then return nil, too_big end
  local entities, tiles = source.get_blueprint_entities() or {}, source.get_blueprint_tiles() or {}
  if limited and prepare.too_many_parts(#entities + #tiles, force_index) then return nil, too_big end
  local first = split(entities)
  local inner = bounds_of(first.buildable, tiles, {})
  local reach = reach_of(inner, entities)
  if limited and too_wide(reach) then return nil, too_big end
  if limited and #first.sockets > const.MAX_DESIGN_SOCKETS then return nil, const.REASON.too_many_sockets end
  local poles = count_type(first.buildable, "electric-pole")
  if limited and poles > const.MAX_DESIGN_POLES then return nil, const.REASON.too_many_poles end
  if not plugs_apart(first.entries) then return nil, "many-entries" end
  if not inner then return nil, "empty-blueprint" end
  return { inner = inner, reach = reach, parts = #entities + #tiles, poles = poles }
end

-- Every other tile when any entity snaps to the 2x2 rail grid.
local function lattice_of(buildable)
  for _, e in ipairs(buildable) do
    local proto = prototypes.entity[e.name]
    if proto and proto.build_grid_size > 1 then return proto.build_grid_size end
  end
  return 1
end

local function cost_of(copy)
  local cost = {}
  for _, item in ipairs(copy.cost_to_build or {}) do
    if not (const.MARKERS[item.name] or const.FOREIGN_MARKERS[item.name]) then
      cost[#cost + 1] = { name = item.name, quality = item.quality, count = item.count }
    end
  end
  return cost
end

-- Writes the stamping copy: no snapping, plus the anchor inside the bounds.
local function write_copy(copy, source, bounds)
  copy.set_stack(source)
  copy.blueprint_snap_to_grid = nil
  local entities = copy.get_blueprint_entities() or {}
  entities[#entities + 1] = {
    entity_number = #entities + 1, name = const.ANCHOR, position = { x = bounds.left + 0.5, y = bounds.top + 0.5 },
  }
  copy.set_blueprint_entities(entities, false)
end

-- The markers as the blueprint wrote them (settings, a socket's target),
-- less the anchor: a blueprint taken over copies writes them back in
-- (blueprint_markers.lua).
local function markers_of(entities)
  local list = {}
  for _, e in ipairs(entities) do
    if (const.MARKERS[e.name] or const.FOREIGN_MARKERS[e.name]) and e.name ~= const.ANCHOR then
      e.entity_number, e.wires = nil, nil
      list[#list + 1] = e
    end
  end
  return list
end

-- `opts.limits`: hold the blueprint to the size limits (registering it).
function prepare.run(design, source, copy, opts)
  local blueprint, why = read(design, source, opts and opts.limits)
  if not blueprint then return fail(design, why) end
  local grid = source.blueprint_snap_to_grid
  local absolute = grid and source.blueprint_absolute_snapping and source.blueprint_position_relative_to_grid
  -- The anchor goes inside the parts and tiles, never on a Keep clear tile;
  -- it never widens the reach.
  write_copy(copy, source, blueprint.inner)
  local tiles = copy.get_blueprint_tiles() or {}
  local copied = copy.get_blueprint_entities() or {}
  local parts = split(copied)
  local force = game.forces[design.force_index]
  local offsets = parts.anchor and calibration.measure(copy, parts.anchor, force, blueprint.reach)
  if not offsets then return fail(design, "calibration-failed", blueprint.parts) end
  local sensor_areas, sensor_categories = sensors.areas(parts.sensors, parts.buildable, entity_box)
  return {
    ok = true, version = design.version, bounds = bounds_of(parts.buildable, tiles, parts.clears), offsets = offsets,
    anchor = parts.anchor, grid = grid and { x = grid.x, y = grid.y } or nil, lattice = lattice_of(parts.buildable),
    absolute = absolute and { x = absolute.x, y = absolute.y } or nil,
    sockets = parts.sockets, entry = main_plug(parts.entries), entries = parts.entries,
    placements = parts.buildable, tiles = tiles,
    sensors = sensor_areas, sensor_categories = sensor_categories, probes = parts.probes, port = parts.ports[1],
    clears = parts.clears, reach = blueprint.reach, parts = blueprint.parts,
    entity_count = #parts.buildable, tile_count = #tiles, pole_count = blueprint.poles, cost = cost_of(copy),
    drill_count = count_type(parts.buildable, "mining-drill"), markers = markers_of(copied),
  }
end

return prepare
