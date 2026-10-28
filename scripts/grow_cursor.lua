-- The design in hand while growing. The window's Grow button puts the chosen
-- design in the cursor as a blueprint with a dashed frame around what a copy
-- covers, so its ghosts follow the pointer and show where the first copy
-- goes. The frame lies on the copy's own edge tiles, so it never moves where
-- the engine puts the blueprint. Its paste never happens: tool.lua takes the
-- click and grows from there.

local const = require("scripts.const")
local library = require("scripts.core.library")
local prepare = require("scripts.core.prepare")

local grow_cursor = {}

-- Frame pieces on the edge tiles of `box`, numbered on from `n`: each faces
-- out, so a corner tile holds two.
local function frame(box, n)
  local list = {}
  local function piece(x, y, direction)
    n = n + 1
    list[#list + 1] = { entity_number = n, name = const.FRAME, position = { x = x + 0.5, y = y + 0.5 }, direction = direction }
  end
  for x = box.left, box.right - 1 do
    piece(x, box.top, defines.direction.north)
    piece(x, box.bottom - 1, defines.direction.south)
  end
  for y = box.top, box.bottom - 1 do
    piece(box.left, y, defines.direction.west)
    piece(box.right - 1, y, defines.direction.east)
  end
  return list
end

-- Writes the design, framed, into `stack`; false if it has no blueprint.
function grow_cursor.write(stack, design)
  local source = library.stack(design)
  if not (source and source.valid_for_read and source.is_blueprint_setup()) then return false end
  local entities, tiles = source.get_blueprint_entities() or {}, source.get_blueprint_tiles() or {}
  local box = prepare.footprint_of(entities, tiles)
  if box then
    box = { left = math.floor(box.left), top = math.floor(box.top), right = math.ceil(box.right), bottom = math.ceil(box.bottom) }
    for _, piece in ipairs(frame(box, #entities)) do entities[#entities + 1] = piece end
  end
  stack.set_stack { name = const.GROW_BLUEPRINT }
  stack.set_blueprint_entities(entities)
  if #tiles > 0 then stack.set_blueprint_tiles(tiles) end
  stack.blueprint_snap_to_grid = source.blueprint_snap_to_grid
  stack.blueprint_absolute_snapping = source.blueprint_absolute_snapping
  stack.blueprint_position_relative_to_grid = source.blueprint_position_relative_to_grid
  stack.label = design.name
  return true
end

function grow_cursor.held(player)
  local stack = player.cursor_stack
  return stack and stack.valid_for_read and stack.name == const.GROW_BLUEPRINT
end

return grow_cursor
