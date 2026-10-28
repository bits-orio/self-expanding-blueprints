-- A design's mirror image, for a paste the player flipped: the engine flips
-- a blueprint only in a player's hand, so its mirror is drawn here, part by
-- part, turned over the blueprint's vertical axis (a vertical flip is that
-- and half a turn). Each part keeps its number, so wires stay; its x is
-- negated and its facing mirrored. Fluid machines take the engine's own
-- mirror flag. What cannot be turned over part by part is refused: rails
-- curve and signals and stops stand on one side of their track.

local mirror = {}

-- Prototype types a mirror is refused for.
local REFUSED = {
  ["straight-rail"] = true, ["half-diagonal-rail"] = true, ["curved-rail-a"] = true, ["curved-rail-b"] = true,
  ["elevated-straight-rail"] = true, ["elevated-half-diagonal-rail"] = true, ["elevated-curved-rail-a"] = true,
  ["elevated-curved-rail-b"] = true, ["rail-ramp"] = true, ["rail-support"] = true, ["legacy-straight-rail"] = true,
  ["legacy-curved-rail"] = true, ["rail-signal"] = true, ["rail-chain-signal"] = true, ["train-stop"] = true,
  ["locomotive"] = true, ["cargo-wagon"] = true, ["fluid-wagon"] = true, ["artillery-wagon"] = true,
}

local SIDE = { left = "right", right = "left" }

local function type_of(name)
  local proto = prototypes.entity[name]
  return proto and proto.type
end

-- The x the mirror turns over: 0, or for a blueprint that snaps to a grid
-- the middle of its grid cell, as the engine turns a snapped blueprint over
-- inside its cell (measured).
local function axis_of(source)
  local grid = source.blueprint_snap_to_grid
  return grid and grid.x or 0
end

-- One part turned over the vertical line x = axis / 2; nil and a reason for
-- a part that cannot be.
local function turned(e, axis)
  local kind = type_of(e.name)
  if REFUSED[kind] then return nil, kind end
  e.position = { x = axis - e.position.x, y = e.position.y }
  if e.direction then e.direction = (16 - e.direction) % 16 end
  e.input_priority = SIDE[e.input_priority] or e.input_priority
  e.output_priority = SIDE[e.output_priority] or e.output_priority
  e.mirror = not e.mirror or nil
  return e
end

-- Writes the mirror of the blueprint `source` into `stack`; false and the
-- refused part's type when it has one.
function mirror.write(stack, source)
  local axis = axis_of(source)
  local entities = source.get_blueprint_entities() or {}
  for i, e in ipairs(entities) do
    local part, refused = turned(e, axis)
    if not part then return false, refused end
    entities[i] = part
  end
  local tiles = source.get_blueprint_tiles() or {}
  for _, t in ipairs(tiles) do t.position = { x = axis - t.position.x - 1, y = t.position.y } end
  stack.set_stack { name = "blueprint" }
  stack.set_blueprint_entities(entities)
  if #tiles > 0 then stack.set_blueprint_tiles(tiles) end
  if source.label and source.label ~= "" then stack.label = source.label end
  if source.blueprint_snap_to_grid then
    stack.blueprint_snap_to_grid = source.blueprint_snap_to_grid
    stack.blueprint_absolute_snapping = source.blueprint_absolute_snapping
    if source.blueprint_absolute_snapping then
      stack.blueprint_position_relative_to_grid = source.blueprint_position_relative_to_grid
    end
  end
  return true
end

return mirror
