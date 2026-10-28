-- A blueprint taken over copies gets their markers back. A copy never has
-- its markers on the map (a stamp destroys their ghosts), so a blueprint of
-- a built copy, made to change the design, would lose its sockets, plugs,
-- sensors, probes, ports and Keep clear tiles. Each copy of the player's
-- team that the selection touches writes its version's markers back in,
-- settings and socket targets as drawn, turned as the copy is; only those
-- inside the selection, and none where the blueprint already holds that
-- marker.

local geometry = require("scripts.core.geometry")
local footprints = require("scripts.core.footprints")
local library = require("scripts.core.library")
local placement = require("scripts.core.placement")

local blueprint_markers = {}

local function copy_of(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = copy_of(v) end
  return out
end

-- The markers of the copy's version: kept with its prepared data, or for a
-- copy whose data predates them, the design's own while it is that version.
local function markers_of(instance)
  local prepared = instance.prepared
  if prepared and prepared.markers then return prepared end
  local design = library.get(instance.force_index, instance.design_id)
  local current = design and design.version == instance.version and design.prepared
  return current and current.markers and current or nil
end

-- What turns a map position into the blueprint's own: one part the engine
-- mapped to the entity it was taken from. Nil when no part was (a blueprint
-- of markers only, or one already turned).
local function shift_of(entities, mapping)
  for _, e in ipairs(entities) do
    local source = mapping[e.entity_number]
    if source and source.valid then
      return { x = e.position.x - source.position.x, y = e.position.y - source.position.y }
    end
  end
end

local function key(name, x, y)
  return name .. "@" .. geometry.position_key({ x = x, y = y })
end

-- The markers to add for one copy, in blueprint coordinates, numbered on.
local function add_copy(instance, area, shift, entities, held)
  local prepared = markers_of(instance)
  if not prepared then return end
  for _, m in ipairs(prepared.markers) do
    local at = placement.world(prepared, m.position, instance.position, instance.direction)
    local x, y = at.x + shift.x, at.y + shift.y
    local k = key(m.name, x, y)
    if prototypes.entity[m.name] and geometry.contains_point(area, at) and not held[k] then
      held[k] = true
      local copy = copy_of(m)
      copy.entity_number, copy.position = #entities + 1, { x = x, y = y }
      if m.direction then copy.direction = geometry.turn(m.direction, instance.direction) end
      entities[#entities + 1] = copy
    end
  end
end

-- `blueprint`: the stack or record just set up from a selection.
function blueprint_markers.add(event, blueprint)
  local player = game.get_player(event.player_index)
  local mapping = event.mapping and event.mapping.valid and event.mapping.get()
  if not (player and mapping and event.area) then return end
  local area = geometry.from_area(event.area)
  local ids = footprints.overlapping(event.surface.index, area)
  if #ids == 0 then return end
  local entities = blueprint.get_blueprint_entities() or {}
  local shift = shift_of(entities, mapping)
  if not shift then return end
  local held = {}
  for _, e in ipairs(entities) do held[key(e.name, e.position.x, e.position.y)] = true end
  local before = #entities
  for _, id in ipairs(ids) do
    local instance = storage.instances[id]
    if instance and instance.force_index == player.force.index then add_copy(instance, area, shift, entities, held) end
  end
  if #entities > before then blueprint.set_blueprint_entities(entities) end
end

return blueprint_markers
