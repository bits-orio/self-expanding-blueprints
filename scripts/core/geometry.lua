-- Pure geometry: quarter-turn rotations, tile-aligned boxes and chunk keys.
-- Boxes are {left, top, right, bottom} in map coordinates; right and bottom
-- are exclusive edges, so two boxes that share an edge do not overlap.

local geometry = {}

local CHUNK = 32
geometry.CHUNK = CHUNK
-- Chunk coordinates stay within +-31250 on the largest map; the offset keeps
-- every key a positive integer that a double holds exactly.
local KEY_OFFSET = 65536
local KEY_STRIDE = 131072

geometry.NORTH = defines.direction.north
geometry.EAST = defines.direction.east
geometry.SOUTH = defines.direction.south
geometry.WEST = defines.direction.west
geometry.CARDINALS = { geometry.NORTH, geometry.EAST, geometry.SOUTH, geometry.WEST }

function geometry.is_cardinal(direction)
  return direction == geometry.NORTH or direction == geometry.EAST
    or direction == geometry.SOUTH or direction == geometry.WEST
end

-- Adds two directions (16-way values); the result is in 0..15.
function geometry.turn(direction, by)
  return (direction + by) % 16
end

-- The rotation that takes `from` onto `to`.
function geometry.turn_between(from, to)
  return (to - from) % 16
end

-- The unit step a cardinal direction points along (north is -y).
function geometry.step(direction)
  if direction == geometry.NORTH then return { x = 0, y = -1 } end
  if direction == geometry.EAST then return { x = 1, y = 0 } end
  if direction == geometry.SOUTH then return { x = 0, y = 1 } end
  return { x = -1, y = 0 }
end

-- Rotates a vector clockwise by a cardinal direction (a quarter-turn count).
function geometry.rotate(v, direction)
  if direction == geometry.EAST then return { x = -v.y, y = v.x } end
  if direction == geometry.SOUTH then return { x = -v.x, y = -v.y } end
  if direction == geometry.WEST then return { x = v.y, y = -v.x } end
  return { x = v.x, y = v.y }
end

-- rotate without allocating: returns x, y
function geometry.rotate_xy(x, y, direction)
  if direction == geometry.EAST then return -y, x end
  if direction == geometry.SOUTH then return -x, -y end
  if direction == geometry.WEST then return y, -x end
  return x, y
end

function geometry.box(left, top, right, bottom)
  return { left = left, top = top, right = right, bottom = bottom }
end

function geometry.box_size(box)
  return { x = box.right - box.left, y = box.bottom - box.top }
end

function geometry.box_center(box)
  return { x = (box.left + box.right) / 2, y = (box.top + box.bottom) / 2 }
end

function geometry.translate_box(box, offset)
  return geometry.box(box.left + offset.x, box.top + offset.y, box.right + offset.x, box.bottom + offset.y)
end

-- Rotates a box about the origin; the result is normalised again.
function geometry.rotate_box(box, direction)
  local a = geometry.rotate({ x = box.left, y = box.top }, direction)
  local b = geometry.rotate({ x = box.right, y = box.bottom }, direction)
  return geometry.box(math.min(a.x, b.x), math.min(a.y, b.y), math.max(a.x, b.x), math.max(a.y, b.y))
end

-- A prototype's box (a BoundingBox) turned to each cardinal direction, as
-- {left, top, right, bottom} offsets about its entity's position.
function geometry.turned(box)
  local l, t, r, b = box.left_top.x, box.left_top.y, box.right_bottom.x, box.right_bottom.y
  return {
    [geometry.NORTH] = { l, t, r, b }, [geometry.EAST] = { -b, l, -t, r },
    [geometry.SOUTH] = { -r, -b, -l, -t }, [geometry.WEST] = { t, -r, b, -l },
  }
end

-- A turned box (geometry.turned) placed at (x, y) facing `direction`: turned
-- for the four cardinal directions, as drawn for the others.
function geometry.placed(turned, x, y, direction)
  local o = turned[direction] or turned[geometry.NORTH]
  return { left = x + o[1], top = y + o[2], right = x + o[3], bottom = y + o[4] }
end

-- The smallest box holding both (either may be nil).
function geometry.union(a, b)
  if not a then return b end
  if not b then return a end
  return geometry.box(math.min(a.left, b.left), math.min(a.top, b.top),
    math.max(a.right, b.right), math.max(a.bottom, b.bottom))
end

-- Rounds outward to whole tiles.
function geometry.tile_box(box)
  return geometry.box(math.floor(box.left), math.floor(box.top), math.ceil(box.right), math.ceil(box.bottom))
end

function geometry.overlaps(a, b)
  return a.left < b.right and b.left < a.right and a.top < b.bottom and b.top < a.bottom
end

function geometry.contains_box(outer, inner)
  return inner.left >= outer.left and inner.top >= outer.top
    and inner.right <= outer.right and inner.bottom <= outer.bottom
end

function geometry.contains_point(box, p)
  return p.x >= box.left and p.x < box.right and p.y >= box.top and p.y < box.bottom
end

-- An engine BoundingBox ({left_top, right_bottom}) for API calls.
function geometry.area(box)
  return { left_top = { x = box.left, y = box.top }, right_bottom = { x = box.right, y = box.bottom } }
end

function geometry.from_area(area)
  local lt = area.left_top or area[1]
  local rb = area.right_bottom or area[2]
  return geometry.box(lt.x or lt[1], lt.y or lt[2], rb.x or rb[1], rb.y or rb[2])
end

function geometry.chunk_key(cx, cy)
  return (cx + KEY_OFFSET) * KEY_STRIDE + (cy + KEY_OFFSET)
end

-- A whole-tile position as one integer, for sets of tiles. Map coordinates
-- stay within +-1e6 tiles, well inside the offset; numbers beat string keys
-- (spike S3 measured string keys about eight times slower).
local TILE_OFFSET = 4194304
local TILE_STRIDE = 8388608

function geometry.tile_key(x, y)
  return (math.floor(x) + TILE_OFFSET) * TILE_STRIDE + (math.floor(y) + TILE_OFFSET)
end

-- The whole-tile position a tile_key holds.
function geometry.tile_xy(key)
  local y = key % TILE_STRIDE
  return (key - y) / TILE_STRIDE - TILE_OFFSET, y - TILE_OFFSET
end

-- The centre of a chunk, in map coordinates.
function geometry.chunk_center(cx, cy)
  return { x = cx * CHUNK + CHUNK / 2, y = cy * CHUNK + CHUNK / 2 }
end

-- Calls fn(cx, cy) for every chunk the box touches.
function geometry.each_chunk(box, fn)
  local x1, y1 = math.floor(box.left / CHUNK), math.floor(box.top / CHUNK)
  local x2, y2 = math.floor((box.right - 1e-6) / CHUNK), math.floor((box.bottom - 1e-6) / CHUNK)
  for cx = x1, x2 do
    for cy = y1, y2 do fn(cx, cy) end
  end
end

-- A position rounded to 1/256 tile and turned into a key, for maps keyed by
-- where something is.
function geometry.position_key(p)
  return math.floor(p.x * 256 + 0.5) .. ":" .. math.floor(p.y * 256 + 0.5)
end

return geometry
