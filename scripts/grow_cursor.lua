-- The design in hand while growing. The window's Grow button puts the chosen
-- design in the cursor as a blueprint with a dashed frame around what a copy
-- covers, so its ghosts follow the pointer and show where the first copy
-- goes. The frame lies on the copy's own edge tiles, so it never moves where
-- the engine puts the blueprint. Its paste never happens: tool.lua takes the
-- click and grows from there. A design handed back after a click comes
-- turned and flipped as that click had it: the engine keeps no turn for a
-- blueprint put into the hand by script, so the parts are turned here.

local const = require("scripts.const")
local library = require("scripts.core.library")
local prepare = require("scripts.core.prepare")
local twins = require("scripts.core.twins")

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

-- A point turned clockwise by `quarters` quarter turns about the origin.
local function rotated(x, y, quarters)
  for _ = 1, quarters do x, y = -y, x end
  return x, y
end

-- The parts and tiles turned by `direction` (a multiple of four), in place.
local function turn(entities, tiles, direction)
  local quarters = math.floor(direction / 4) % 4
  if quarters == 0 then return end
  for _, e in ipairs(entities) do
    e.position.x, e.position.y = rotated(e.position.x, e.position.y, quarters)
    local proto = prototypes.entity[e.name]
    if proto and proto.supports_direction then e.direction = ((e.direction or 0) + direction) % 16 end
  end
  -- A tile is named by its corner: its middle is turned.
  for _, t in ipairs(tiles) do
    local x, y = rotated(t.position.x + 0.5, t.position.y + 0.5, quarters)
    t.position = { x = x - 0.5, y = y - 0.5 }
  end
end

-- The blueprint to show for the design held turned and flipped as `turned`
-- ({direction, mirrored}): a flip shows its mirror twin, and the turn is
-- left out of a snapped blueprint, whose grid would turn too. Also the turn
-- and flip it really holds.
local function source_of(design, turned)
  local mirrored, direction = turned and turned.mirrored == true, turned and turned.direction or 0
  local shown = mirrored and twins.of(design) or design
  if not shown then shown, mirrored = design, false end
  local source = library.stack(shown)
  if source and source.valid_for_read and source.blueprint_snap_to_grid then direction = 0 end
  return source, { direction = direction, mirrored = mirrored }
end

-- Writes the design, framed, into `stack`, turned and flipped as `turned`
-- (optional); returns the turn and flip it holds, or false if it has no
-- blueprint.
function grow_cursor.write(stack, design, turned)
  local source, holds = source_of(design, turned)
  if not (source and source.valid_for_read and source.is_blueprint_setup()) then return false end
  local entities, tiles = source.get_blueprint_entities() or {}, source.get_blueprint_tiles() or {}
  turn(entities, tiles, holds.direction)
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
  return holds
end

function grow_cursor.held(player)
  local stack = player.cursor_stack
  return stack and stack.valid_for_read and stack.name == const.GROW_BLUEPRINT
end

return grow_cursor
