-- Where a stamp lands. A design's prepared data says, per build direction d,
-- where build_blueprint puts its blueprint origin relative to the build
-- position P (offsets[d], measured by calibration). Everything else follows:
--   world(bp, P, d) = P + offsets[d] + rotate(bp, d)
-- Build positions stay on the design's lattice (whole tiles, or every other
-- tile for designs whose entities snap to the 2x2 rail grid), so each stamp
-- reproduces the calibrated offsets exactly.

local const = require("scripts.const")
local geometry = require("scripts.core.geometry")

local placement = {}

local function lattice_round(value, lattice)
  return math.floor(value / lattice + 0.5) * lattice
end

-- Rounds a seed onto the lattice; a seed has no exact target to miss.
local function on_lattice(prepared, p)
  local lattice = prepared.lattice or 1
  return { x = lattice_round(p.x, lattice), y = lattice_round(p.y, lattice) }
end

-- A placement aimed at an exact point must already sit on the lattice:
-- build_blueprint would snap it and the entry would miss its socket.
local function exact(prepared, p, direction)
  local lattice = prepared.lattice or 1
  if math.floor(p.x / lattice) * lattice ~= p.x or math.floor(p.y / lattice) * lattice ~= p.y then
    return nil, const.REASON.off_grid
  end
  return p, direction
end

function placement.world(prepared, bp, position, direction)
  local o = prepared.offsets[direction]
  local r = geometry.rotate(bp, direction)
  return { x = position.x + o.x + r.x, y = position.y + o.y + r.y }
end

-- A box drawn in blueprint coordinates, in world space.
function placement.area(prepared, box, position, direction)
  local o = prepared.offsets[direction]
  return geometry.translate_box(geometry.rotate_box(box, direction), { x = position.x + o.x, y = position.y + o.y })
end

function placement.footprint(prepared, position, direction)
  return placement.area(prepared, prepared.bounds, position, direction)
end

-- The design's parts in world space, for a stamp at `position` facing
-- `direction`, until fn returns true: fn(part, x, y, facing) for each
-- entity part.
function placement.each_part(prepared, position, direction, fn)
  local o = prepared.offsets[direction]
  local ox, oy = position.x + o.x, position.y + o.y
  for _, e in ipairs(prepared.placements) do
    local rx, ry = geometry.rotate_xy(e.position.x, e.position.y, direction)
    if fn(e, ox + rx, oy + ry, geometry.turn(e.direction, direction)) then return end
  end
end

-- fn(tile, x, y) for each design tile, (x, y) the world tile it lands on.
function placement.each_tile(prepared, position, direction, fn)
  local o = prepared.offsets[direction]
  local ox, oy = position.x + o.x, position.y + o.y
  for _, tile in ipairs(prepared.tiles or {}) do
    local rx, ry = geometry.rotate_xy(tile.position.x + 0.5, tile.position.y + 0.5, direction)
    if fn(tile, math.floor(ox + rx), math.floor(oy + ry)) then return end
  end
end

-- fn(x, y) for each Keep clear tile, in world tiles.
function placement.each_kept(prepared, position, direction, fn)
  local o = prepared.offsets[direction]
  local ox, oy = position.x + o.x, position.y + o.y
  for _, p in ipairs(prepared.clears or {}) do
    local rx, ry = geometry.rotate_xy(p.x, p.y, direction)
    if fn(math.floor(ox + rx), math.floor(oy + ry)) then return end
  end
end

-- The stamp's drawn sockets in world space.
function placement.sockets(prepared, position, direction)
  local list = {}
  for i, socket in ipairs(prepared.sockets) do
    list[i] = {
      position = placement.world(prepared, socket.position, position, direction),
      direction = geometry.turn(socket.direction, direction),
      target = socket.target, number = socket.number,
    }
  end
  return list
end

-- The blueprint's snap grid as seen by a stamp facing `direction`: its axes
-- swap for east and west.
local function turned_grid(prepared, direction)
  local g = prepared.grid
  if direction == geometry.EAST or direction == geometry.WEST then return { x = g.y, y = g.x } end
  return { x = g.x, y = g.y }
end

-- The repeat size of a stamp facing `direction`: the blueprint's snap grid
-- when it has one, else its footprint, rounded up onto the lattice.
function placement.repeat_size(prepared, direction)
  local size = prepared.grid and turned_grid(prepared, direction)
    or geometry.box_size(geometry.rotate_box(prepared.bounds, direction))
  local lattice = prepared.lattice or 1
  return { x = math.ceil(size.x / lattice) * lattice, y = math.ceil(size.y / lattice) * lattice }
end

-- Level 1 implicit socket: the next copy, same design and direction, one
-- repeat further along `toward`. It is placed by its corner against the
-- parent's recorded footprint and repeat, not the parent's build position,
-- so a design updated mid-project still abuts its older copies (or keeps the
-- grid's gaps): east and south step by the parent's repeat, west and north
-- by the child's own.
function placement.implicit_child(prepared, parent, toward)
  local direction = parent.direction
  local back = parent.repeat_size
  local own = placement.repeat_size(prepared, direction)
  local box = parent.footprint
  local corner = { x = box.left, y = box.top }
  if toward == geometry.EAST then corner.x = box.left + back.x
  elseif toward == geometry.WEST then corner.x = box.left - own.x
  elseif toward == geometry.SOUTH then corner.y = box.top + back.y
  else corner.y = box.top - own.y end
  -- A plain corner step: from a parent on the world grid, one grid further
  -- is on it too, and a design updated mid-project still abuts.
  return placement.at_corner(prepared, corner, direction), direction
end

-- The build position that puts the design's entry arrow on the tile holding
-- `point` when built facing `direction`. A design without an entry lands by
-- its vanilla anchor (placement.anchor). Returns nil and "off-grid" when an
-- entry target is off the design's lattice.
function placement.by_entry(prepared, point, direction, entry)
  entry = entry or prepared.entry
  if not entry then return placement.anchor(prepared, point, direction) end
  local o = prepared.offsets[direction]
  local r = geometry.rotate(entry.position, direction)
  -- The arrow is one tile, so it always sits on a tile centre.
  local x, y = math.floor(point.x) + 0.5, math.floor(point.y) + 0.5
  return exact(prepared, { x = x - o.x - r.x, y = y - o.y - r.y }, direction)
end

-- A child without an entry attaches by the middle of its back edge,
-- unturned: that edge's row is the socket's tile, centred along it. It is
-- the entry rule with an implied entry, so a socket on the first tile outside
-- the parent fits flush whether the child has an entry or not.
local function by_edge(prepared, socket)
  local size = geometry.box_size(prepared.bounds)
  local step, p = geometry.step(socket.direction), socket.position
  local centre = { x = p.x + step.x * (size.x / 2 - 0.5), y = p.y + step.y * (size.y / 2 - 0.5) }
  local at = placement.centred_on(prepared, centre, geometry.NORTH)
  -- Along the edge the centring may round; across it the child must start on
  -- the socket's tile, so a lattice that cannot put it there closes the
  -- socket as off-grid instead of leaving a gap or an overlap.
  local c0 = geometry.box_center(placement.footprint(prepared, { x = 0, y = 0 }, geometry.NORTH))
  if (step.x ~= 0 and at.x ~= centre.x - c0.x) or (step.y ~= 0 and at.y ~= centre.y - c0.y) then
    return nil, const.REASON.off_grid
  end
  return at, geometry.NORTH
end

-- The plug a socket attaches: the one with the socket's number; for a
-- socket without one, the design's main plug (prepare.lua). Nil when no
-- plug has the number.
function placement.plug_for(prepared, socket)
  if not socket.number then return prepared.entry end
  for _, entry in ipairs(prepared.entries or { prepared.entry }) do
    if entry.number == socket.number then return entry end
  end
  return nil
end

-- A child on a drawn socket: its plug lands on the socket facing the same
-- way, or, with no plug at all, it attaches by its back edge (by_edge).
-- Also returns the plug used, or nil and "no-plug" when a numbered socket
-- names a plug the design lacks.
function placement.on_socket(prepared, socket)
  if not prepared.entry then
    if socket.number then return nil, const.REASON.no_plug end
    return by_edge(prepared, socket)
  end
  local entry = placement.plug_for(prepared, socket)
  if not entry then return nil, const.REASON.no_plug end
  local position, direction = placement.by_entry(prepared, socket.position,
    geometry.turn_between(entry.direction, socket.direction), entry)
  return position, direction, entry
end

-- Where a plug (the main one unless given) of a stamp at `position` facing
-- `direction` lands.
function placement.entry_at(prepared, position, direction, entry)
  entry = entry or prepared.entry
  return entry and placement.world(prepared, entry.position, position, direction)
end

-- A blueprint with absolute snapping snaps to world grid lines at
-- rel + k * grid (the grid turned for east and west, rel in world axes). Its
-- origin goes to the top-left of the cell holding the build position, then
-- to the cell corner the turned origin lands on (spike S1, Q1 f). Our copy
-- has snapping cleared, so the build position reproducing a cell is that
-- corner minus offsets[d].
local ORIGIN_CORNER = {
  [geometry.NORTH] = { x = 0, y = 0 }, [geometry.EAST] = { x = 1, y = 0 },
  [geometry.SOUTH] = { x = 1, y = 1 }, [geometry.WEST] = { x = 0, y = 1 },
}

-- The build position for the world grid cell `round` picks around `p`:
-- math.floor for the cell holding p, math.ceil for the first cell at or
-- after it.
local function in_cell(prepared, p, direction, round)
  local g, rel = turned_grid(prepared, direction), prepared.absolute
  local corner = { x = rel.x + round((p.x - rel.x) / g.x) * g.x, y = rel.y + round((p.y - rel.y) / g.y) * g.y }
  local k, o = ORIGIN_CORNER[direction], prepared.offsets[direction]
  return on_lattice(prepared, { x = corner.x + k.x * g.x - o.x, y = corner.y + k.y * g.y - o.y })
end

-- A seed whose footprint is centred on `point`.
function placement.centred_on(prepared, point, direction)
  local centre = geometry.box_center(placement.footprint(prepared, { x = 0, y = 0 }, direction))
  return on_lattice(prepared, { x = point.x - centre.x, y = point.y - centre.y })
end

-- The vanilla anchor at `point` (a grow-tool click, a stamp without an
-- entry): where the player's own blueprint would land with the cursor
-- there. Absolute snapping picks the world grid cell holding the point;
-- otherwise the footprint is centred on it.
function placement.anchor(prepared, point, direction)
  if prepared.absolute then return in_cell(prepared, point, direction, math.floor) end
  return placement.centred_on(prepared, point, direction)
end

-- The build position whose footprint starts at `corner`, rounded up onto the
-- lattice so the footprint never starts before the corner. No world grid.
function placement.at_corner(prepared, corner, direction)
  local box = placement.footprint(prepared, { x = 0, y = 0 }, direction)
  local lattice = prepared.lattice or 1
  local x = math.ceil((corner.x - box.left) / lattice - 1e-6) * lattice
  local y = math.ceil((corner.y - box.top) / lattice - 1e-6) * lattice
  return { x = x, y = y }
end

-- With absolute snapping the build positions that land on the world grid are
-- rel - offsets[d] + k * grid; this is the first of them whose footprint
-- starts at or after `corner`, wherever the content sits in its cell.
local function first_on_grid(prepared, corner, direction)
  local g, rel, o = turned_grid(prepared, direction), prepared.absolute, prepared.offsets[direction]
  local box = placement.footprint(prepared, { x = 0, y = 0 }, direction)
  local x = rel.x - o.x + math.ceil((corner.x - box.left - rel.x + o.x) / g.x - 1e-6) * g.x
  local y = rel.y - o.y + math.ceil((corner.y - box.top - rel.y + o.y) / g.y - 1e-6) * g.y
  return on_lattice(prepared, { x = x, y = y })
end

-- A seed whose footprint's top-left corner is at `corner` (a grow-tool drag);
-- with absolute snapping, the first placement on the world grid from there.
function placement.top_left_at(prepared, corner, direction)
  if prepared.absolute then return first_on_grid(prepared, corner, direction) end
  return placement.at_corner(prepared, corner, direction)
end

-- Where a fill's first copy goes: the area's top-left corner, or the corner
-- the drag started at (from_right, from_bottom), the copy inside it.
local function fill_corner(prepared, where, direction)
  local area, size = where.area, placement.repeat_size(prepared, direction)
  return {
    x = where.from_right and area.right - size.x or area.left,
    y = where.from_bottom and area.bottom - size.y or area.top,
  }
end

-- Where a seed lands, from one of: build_position (used as given, so it must
-- sit on the lattice), position (as a remote stamp: the entry arrow lands
-- there), area (filled from the corner the drag started at, see fill_corner)
-- or point (the vanilla anchor there, as a click). Returns the build
-- position, or nil and a reason.
function placement.seed(prepared, where, direction)
  if where.build_position then return exact(prepared, where.build_position, direction) end
  if where.position then return placement.by_entry(prepared, where.position, direction) end
  if where.area then return placement.top_left_at(prepared, fill_corner(prepared, where, direction), direction) end
  return placement.anchor(prepared, where.point, direction)
end

return placement
