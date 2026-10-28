-- An instance's own ghosts. Entity ghosts carry the instance's tag; tile
-- ghosts cannot hold tags, so they are known by unit number. Shared by the
-- stamp (tag and watch), the recount (count) and retirement (destroy).

local const = require("scripts.const")
local under = require("scripts.core.under")

local ghosts = {}

-- A ghost of a socket, entry or anchor arrow: never built by robots.
function ghosts.is_marker(entity)
  return entity.type == "entity-ghost" and const.MARKERS[entity.ghost_name] ~= nil
end

-- A ghost of another mod's marker a design carries (const.FOREIGN_MARKERS):
-- removed from our own stamps, left alone anywhere else.
function ghosts.is_foreign_marker(entity)
  return entity.type == "entity-ghost" and const.FOREIGN_MARKERS[entity.ghost_name] ~= nil
end

function ghosts.tag(ghost, id)
  local tags = ghost.tags or {}
  tags[const.TAG] = id
  ghost.tags = tags
end

-- Makes the object's end (built, mined or removed) mark the instance dirty.
-- Registering twice is harmless: the engine returns the same number.
function ghosts.watch(object, id)
  local reg = script.register_on_object_destroyed(object)
  storage.ghost_regs[reg] = id
  return reg
end

-- Calls fn(ghost) for each entity ghost and tile ghost of the instance:
-- the entity ghosts under its parts, the tile ghosts on its tiles.
function ghosts.each(surface, instance, fn)
  local id, force = instance.id, instance.force_index
  under.each(surface, nil, under.instance_boxes(instance), { type = "entity-ghost", force = force }, function(ghost)
    local tags = ghost.tags
    if tags and tags[const.TAG] == id then fn(ghost) end
  end)
  if not next(instance.tile_units) then return end
  under.each(surface, nil, under.tile_boxes(instance.tiles), { type = "tile-ghost", force = force }, function(ghost)
    if instance.tile_units[ghost.unit_number] then fn(ghost) end
  end)
end

return ghosts
