-- The rectangle of an area verb (Sense, Clear, Upgrade), worked through a
-- piece at a time: its part in each map chunk, row by row. A read takes
-- pieces while the team may work (D44), and never more than MAX_PIECES, so
-- even 512 x 512 tiles are spread over reads; each piece is charged by its
-- tiles and by what was done in it.

local budget = require("scripts.core.budget")

local sweep = {}

local CHUNK = 32
local MAX_PIECES = 16

-- box: {left, top, right, bottom}, whole tiles.
function sweep.begin(request, box)
  local cx, cy = math.floor(box.left / CHUNK), math.floor(box.top / CHUNK)
  local columns = math.floor((box.right - 1) / CHUNK) - cx + 1
  local rows = math.floor((box.bottom - 1) / CHUNK) - cy + 1
  request.sweep = { box = box, cx = cx, cy = cy, columns = columns, count = columns * rows, next = 0 }
end

local function piece(s, k)
  local cx, cy = s.cx + k % s.columns, s.cy + math.floor(k / s.columns)
  local box = s.box
  return {
    left = math.max(box.left, cx * CHUNK), top = math.max(box.top, cy * CHUNK),
    right = math.min(box.right, (cx + 1) * CHUNK), bottom = math.min(box.bottom, (cy + 1) * CHUNK),
  }
end

-- An engine BoundingBox for a piece.
function sweep.area(p)
  return { { p.left, p.top }, { p.right, p.bottom } }
end

-- Runs work(piece) on the pieces left while the team may work; work
-- returns the microseconds it cost beyond the piece's tiles. True once
-- every piece is done (also for a request taken before rectangles went a
-- piece at a time: it did all of its work when it was taken).
function sweep.run(request, force_index, work)
  local s = request.sweep
  if not s then return true end
  for _ = 1, MAX_PIECES do
    if s.next >= s.count then return true end
    if not budget.ready(force_index) then return false end
    local p = piece(s, s.next)
    local cost = work(p) + (p.right - p.left) * (p.bottom - p.top) * budget.COST.area_tile
    s.next = s.next + 1
    budget.charge(force_index, cost)
  end
  return s.next >= s.count
end

-- Whether an entity a piece found is the piece's own: one across a piece
-- edge is found by each piece it touches, and belongs to the one holding
-- its position (brought into the rectangle when it lies outside), so it
-- is counted once, as one search over the whole rectangle would.
function sweep.owns(request, p, position)
  local box = request.sweep.box
  local x = math.min(math.max(position.x, box.left), box.right)
  local y = math.min(math.max(position.y, box.top), box.bottom)
  return x >= p.left and (x < p.right or p.right == box.right)
    and y >= p.top and (y < p.bottom or p.bottom == box.bottom)
end

-- The entities in `list` from `start` on whose wait `waits(entity)` says
-- is over, skipped for good: the index of the first still waiting, or nil
-- when none is. Every read then looks only from there.
function sweep.first_waiting(list, start, waits)
  for i = start or 1, #list do
    local e = list[i]
    if e.valid and waits(e) then return i end
  end
end

return sweep
