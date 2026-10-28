-- What stands under a copy's parts, without reading its whole footprint: a
-- design of two lamps 400 tiles apart has a footprint of 160,000 tiles, and
-- one query over it looks at every entity there. Callers hand in boxes (map
-- boxes): each entity part's collision box, turned and placed, and design
-- tiles and Keep clear tiles as whole tiles.
--
-- Measured on 2.1 headless: one small query costs 1.5 to 4 µs (a long type
-- list costs most), one query over an area about 0.08 µs per entity in it.
-- So where the boxes are dense (their bound holds at most DENSE tiles per
-- box) one count over the bound, which costs about what DENSE small queries
-- would, says whether anything there matches at all; when something does,
-- or the boxes are sparse, each box is read on its own (consecutive boxes
-- that make one rectangle, a row of tiles, as one). The cost follows the
-- number of boxes, never the bound's area. The engine decides every match:
-- a cliff's bounding_box does not hold its shape, so nothing is tested here
-- by bounding box. Area queries count what only touches an area's edge, and
-- map geometry comes in 1/256 tile steps, so each box is read 1/256 smaller:
-- a match overlaps the box.

local geometry = require("scripts.core.geometry")
local placement = require("scripts.core.placement")

local under = {}

local DENSE = 8
local STEP = 1 / 256
-- Rails reach past their collision box and their tiles: measured on 2.1, a
-- curved rail reaches 4 tiles from its position, a straight one 2.
local RAIL_REACH = 4
local RAILS = {
  ["straight-rail"] = true, ["half-diagonal-rail"] = true, ["curved-rail-a"] = true, ["curved-rail-b"] = true,
  ["legacy-straight-rail"] = true, ["legacy-curved-rail"] = true, ["rail-ramp"] = true,
  ["elevated-straight-rail"] = true, ["elevated-half-diagonal-rail"] = true,
  ["elevated-curved-rail-a"] = true, ["elevated-curved-rail-b"] = true,
}

-- Per entity name, constant for the session (prototypes cannot change while
-- the script runs; rebuilt on every load): its collision box turned to each
-- cardinal direction (geometry.turned), and the half-size of a square that
-- holds it turned any way (rails: their reach).
local shapes = {}

local function shape_of(name)
  local shape = shapes[name]
  if shape ~= nil then return shape end
  local proto = prototypes.entity[name]
  shape = false
  if proto then
    local cb = proto.collision_box
    local l, t, r, b = cb.left_top.x, cb.left_top.y, cb.right_bottom.x, cb.right_bottom.y
    shape = geometry.turned(cb)
    shape.radius = math.sqrt(math.max(l * l, r * r) + math.max(t * t, b * b))
    shape.reach = RAILS[proto.type] and math.max(RAIL_REACH, shape.radius) or nil
  end
  shapes[name] = shape
  return shape
end

-- The box a part of `name` at (x, y) facing `direction` may collide in, or
-- nil when its prototype is gone: its collision box turned for the four
-- cardinal directions, else the square that holds it turned any way.
function under.part_box(name, x, y, direction)
  local s = shape_of(name)
  if not s then return nil end
  local o = not s.reach and s[direction]
  if o then return { left = x + o[1], top = y + o[2], right = x + o[3], bottom = y + o[4] } end
  local h = s.reach or s.radius
  return { left = x - h, top = y - h, right = x + h, bottom = y + h }
end

-- The collision box of a part of `name` at (x, y) facing `direction`
-- (geometry.placed): what the part stands on (rails reach further, see
-- part_box). nil when its prototype is gone.
function under.collision_box(name, x, y, direction)
  local s = shape_of(name)
  return s and geometry.placed(s, x, y, direction) or nil
end

local function tile_box(x, y)
  return { left = x, top = y, right = x + 1, bottom = y + 1 }
end

-- Each kind of a design's parts as boxes, in world space.
local KINDS = {
  -- Each entity part's box, with the part's name.
  entities = function(prepared, position, direction)
    local list = {}
    placement.each_part(prepared, position, direction, function(e, x, y, facing)
      local box = under.part_box(e.name, x, y, facing)
      if box then
        box.name = e.name
        list[#list + 1] = box
      end
    end)
    return list
  end,
  tiles = function(prepared, position, direction)
    local list = {}
    placement.each_tile(prepared, position, direction, function(_, x, y) list[#list + 1] = tile_box(x, y) end)
    return list
  end,
  -- Keep clear tiles.
  kept = function(prepared, position, direction)
    local list = {}
    placement.each_kept(prepared, position, direction, function(x, y) list[#list + 1] = tile_box(x, y) end)
    return list
  end,
}

-- A plan's boxes of one kind ("entities", "tiles" or "kept"), made once and
-- kept on the plan, which lives for one check and its stamp.
function under.boxes(plan, kind)
  plan.parts = plan.parts or {}
  local list = plan.parts[kind]
  if not list then
    list = KINDS[kind](plan.prepared, plan.position, plan.direction)
    plan.parts[kind] = list
  end
  return list
end

-- The last copy's boxes, as a recount looks at them two or three times in a
-- row; made again whenever its version, position or direction changed.
local recent = {}

-- Whether a stamped copy records where its parts are: the prepared data of
-- its version (set at stamp time). A copy stamped before that, or whose
-- version moved on without it, is looked at over its whole footprint.
function under.knows_parts(instance)
  local prepared = instance.prepared
  return prepared ~= nil and prepared.version == instance.version
end

-- A stamped copy's entity part boxes, or its footprint (under.knows_parts).
function under.instance_boxes(instance)
  local prepared = instance.prepared
  if not under.knows_parts(instance) then return { instance.footprint } end
  if recent.instance ~= instance or recent.prepared ~= prepared or recent.position ~= instance.position
    or recent.direction ~= instance.direction then
    recent = {
      instance = instance, prepared = prepared, position = instance.position, direction = instance.direction,
      boxes = KINDS.entities(prepared, instance.position, instance.direction),
    }
  end
  return recent.boxes
end

-- Whole-tile boxes of a set {[tile_key] = name}.
function under.tile_boxes(tiles)
  local list = {}
  for key in pairs(tiles) do list[#list + 1] = tile_box(geometry.tile_xy(key)) end
  return list
end

-- The boxes of both lists, as one.
function under.join(a, b)
  local list = {}
  for _, box in ipairs(a) do list[#list + 1] = box end
  for _, box in ipairs(b) do list[#list + 1] = box end
  return list
end

local function flat(box)
  return box.right - box.left <= 2 * STEP or box.bottom - box.top <= 2 * STEP
end

-- The boxes to read: consecutive ones that make one rectangle (same rows,
-- touching or overlapping columns, or the other way round) as one. A box
-- is copied only when it grows.
local function merged(boxes)
  if #boxes < 2 then return boxes end
  local list, last, own = {}, nil, false
  for _, b in ipairs(boxes) do
    local rows = last and not flat(b) and not flat(last) and last.top == b.top and last.bottom == b.bottom
      and b.left <= last.right and b.right >= last.left
    local columns = last and not rows and not flat(b) and not flat(last) and last.left == b.left
      and last.right == b.right and b.top <= last.bottom and b.bottom >= last.top
    if rows or columns then
      if not own then
        last, own = geometry.box(last.left, last.top, last.right, last.bottom), true
        list[#list] = last
      end
      last.left, last.top = math.min(last.left, b.left), math.min(last.top, b.top)
      last.right, last.bottom = math.max(last.right, b.right), math.max(last.bottom, b.bottom)
    else
      last, own = b, false
      list[#list + 1] = b
    end
  end
  return list
end

-- The engine area that reads `box`: 1/256 smaller on every side, so what
-- only touches it is left out; a box too thin for that is read as it is.
local function set_area(area, box)
  local inset = flat(box) and 0 or STEP
  area.left_top.x, area.left_top.y = box.left + inset, box.top + inset
  area.right_bottom.x, area.right_bottom.y = box.right - inset, box.bottom - inset
end

-- One count's filter, kept: under.any sets all of its fields each time.
local ANY = { area = { left_top = {}, right_bottom = {} }, type = "", limit = 1 }

-- Whether an entity of `type` overlaps the box (nil: none can): one count,
-- with no table made, for a check that runs for every part.
function under.any(surface, box, type)
  if not box then return false end
  set_area(ANY.area, box)
  ANY.type = type
  return surface.count_entities_filtered(ANY) > 0
end

local function bound_of(boxes, bound)
  local u = bound
  for _, box in ipairs(boxes) do u = geometry.union(u, box) end
  return u
end

-- Whether a dense set of boxes has nothing matching anywhere in its bound.
local function none_in(surface, query, boxes, bound)
  local u = bound_of(boxes, bound)
  if (u.right - u.left) * (u.bottom - u.top) > DENSE * #boxes then return false end
  local limit = query.limit
  set_area(query.area, u)
  query.limit = 1
  local none = surface.count_entities_filtered(query) == 0
  query.limit = limit
  return none
end

-- Whether the entity is met for the first time: by unit number, else by
-- name and position (in 1/256 steps from `origin`).
local function first_time(seen, e, origin)
  local unit = e.unit_number
  if unit then
    if seen.units[unit] then return false end
    seen.units[unit] = true
    return true
  end
  local p, name = e.position, e.name
  local key = (math.floor((p.x - origin.left) * 256 + 0.5) + 1048576) * 2097152
    + math.floor((p.y - origin.top) * 256 + 0.5) + 1048576
  local at = seen.at[name] or {}
  seen.at[name] = at
  if at[key] then return false end
  at[key] = true
  return true
end

-- What fn returns to end a walk early (nothing else it returns does).
under.STOP = {}

-- Calls fn(entity, box) once per entity matching `filter` (a
-- find_entities_filtered filter without area or position) that overlaps one
-- of `boxes`; `box` is the box read when it was found (a merged row of them,
-- perhaps). fn returning under.STOP ends the walk. `bound` is a box the
-- count may read besides the boxes (a copy's footprint), or nil. A limit in
-- the filter applies to each box read.
function under.each(surface, bound, boxes, filter, fn)
  if #boxes == 0 then return end
  local query = { area = { left_top = {}, right_bottom = {} } }
  for k, v in pairs(filter) do query[k] = v end
  if #boxes > 1 and none_in(surface, query, boxes, bound) then return end
  local reads = merged(boxes)
  local seen = #reads > 1 and { units = {}, at = {} } or nil
  for _, box in ipairs(reads) do
    set_area(query.area, box)
    for _, e in ipairs(surface.find_entities_filtered(query)) do
      if (not seen or first_time(seen, e, reads[1])) and fn(e, box) == under.STOP then return end
    end
  end
end

return under
