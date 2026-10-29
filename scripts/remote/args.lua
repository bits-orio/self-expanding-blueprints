-- Checks the remote interface's arguments at the boundary. A bad call gets
-- nil and "invalid-<field>" back at once, instead of storing a value that
-- fails later inside a scheduled handler, where the error names no caller.

local geometry = require("scripts.core.geometry")

local args = {}

local function finite(n)
  return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

-- The engine makes no map beyond +-1,000,000 tiles: a place past it would
-- wait for chunks that never come, and one far beyond fails in the engine.
local MAP_LIMIT = 1000000

local function on_map(n)
  return finite(n) and n >= -MAP_LIMIT and n <= MAP_LIMIT
end

local function integer_from(min)
  return function(n)
    if finite(n) and n >= min and n % 1 == 0 then return n end
  end
end

-- {x =, y =} or {x, y} on the map, as a fresh {x, y}.
function args.position(value)
  if type(value) ~= "table" then return nil end
  local x, y = value.x or value[1], value.y or value[2]
  if on_map(x) and on_map(y) then return { x = x, y = y } end
end

local function corners(value)
  local lt, rb = args.position(value.left_top or value[1]), args.position(value.right_bottom or value[2])
  return lt and rb and geometry.box(lt.x, lt.y, rb.x, rb.y)
end

local function edges(value)
  if on_map(value.left) and on_map(value.top) and on_map(value.right) and on_map(value.bottom) then
    return geometry.box(value.left, value.top, value.right, value.bottom)
  end
end

-- {left, top, right, bottom}, {left_top =, right_bottom =} or {{x, y}, {x, y}},
-- as a whole-tile box that is not empty (rounded outward, like a drag).
function args.area(value)
  if type(value) ~= "table" then return nil end
  local box = (value.left_top or value[1]) and corners(value) or edges(value)
  if box and box.right > box.left and box.bottom > box.top then return geometry.tile_box(box) end
end

local function cardinal(value)
  if geometry.is_cardinal(value) then return value end
end

-- A list of cardinal directions, in the caller's order; a repeat refuses
-- the whole list.
local function cardinals(value)
  if type(value) ~= "table" then return nil end
  local list, seen = {}, {}
  for _, d in ipairs(value) do
    if not geometry.is_cardinal(d) then return nil end
    if not seen[d] then list[#list + 1], seen[d] = d, true end
  end
  if #list == #value then return list end
end

local function boolean(value)
  if type(value) == "boolean" then return value end
end

local ORDERS = { breadth = true, depth = true, nearest = true }
local function order(value)
  if ORDERS[value] then return value end
end

local function preview_count(value)
  local n = integer_from(0)(value)
  if n and n <= 20 then return n end
end

local CHECKS = {
  position = args.position, build_position = args.position, point = args.position, area = args.area,
  direction = cardinal, directions = cardinals, materials = boolean, charted_only = boolean, retire_depleted = boolean, dry_run = boolean, open_early = boolean,
  max_instances = integer_from(1), max_building = integer_from(1), reserve = integer_from(0),
  radius = integer_from(1), enemy_distance = integer_from(0), landfill = boolean, order = order,
  superforce = boolean, preview_ghosts = preview_count, mirrored = boolean, sides_with_sockets = boolean,
}

-- Copies the listed fields of a call's params, each checked and normalised,
-- and requires exactly one of the `place` fields (where the stamp goes).
-- Returns the copy, or nil and "invalid-<field>" for the first field that
-- fails; a missing or doubled place is "invalid-position".
function args.read(params, fields, place)
  local out = {}
  for _, field in ipairs(fields) do
    local value = params[field]
    if value ~= nil then
      value = CHECKS[field](value)
      if value == nil then return nil, "invalid-" .. field end
      out[field] = value
    end
  end
  local given = 0
  for _, field in ipairs(place) do
    if out[field] ~= nil then given = given + 1 end
  end
  if given ~= 1 then return nil, "invalid-position" end
  return out
end

-- A design name: nil (use the blueprint's label) or a non-empty string.
function args.name(value)
  return value == nil or (type(value) == "string" and value ~= "")
end

return args
