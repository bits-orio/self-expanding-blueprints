-- Quarter-turn rotations, footprint bounds and the placement models under test.
local G = {}
local floor = math.floor

-- R_d: north (x, y); east (-y, x); south (-x, -y); west (y, -x)
function G.rot(v, d)
  if d == 0 then return {x = v.x, y = v.y} end
  if d == 4 then return {x = -v.y, y = v.x} end
  if d == 8 then return {x = -v.x, y = -v.y} end
  if d == 12 then return {x = v.y, y = -v.x} end
  error("non-cardinal direction " .. tostring(d))
end

function G.add(a, b) return {x = a.x + b.x, y = a.y + b.y} end
function G.sub(a, b) return {x = a.x - b.x, y = a.y - b.y} end
function G.same(a, b) return math.abs(a.x - b.x) < 1e-6 and math.abs(a.y - b.y) < 1e-6 end
function G.frac(v) return v - floor(v) end

local function union(acc, b)
  if not acc then return {l = b.l, t = b.t, r = b.r, b = b.b} end
  acc.l = math.min(acc.l, b.l)
  acc.t = math.min(acc.t, b.t)
  acc.r = math.max(acc.r, b.r)
  acc.b = math.max(acc.b, b.b)
  return acc
end

function G.rot_box(b, d)
  local p1 = G.rot({x = b.l, y = b.t}, d)
  local p2 = G.rot({x = b.r, y = b.b}, d)
  return {
    l = math.min(p1.x, p2.x), t = math.min(p1.y, p2.y),
    r = math.max(p1.x, p2.x), b = math.max(p1.y, p2.y),
  }
end

-- Footprint of one blueprint entity in blueprint coordinates.
-- mode "tile": tile_width x tile_height (swapped for east/west);
-- mode "coll": the prototype collision box rotated by the entity direction.
function G.entity_box(e, mode)
  local proto = prototypes.entity[e.name]
  local dir = e.direction or 0
  local box
  if mode == "tile" then
    local w, h = proto.tile_width, proto.tile_height
    box = {l = -w / 2, t = -h / 2, r = w / 2, b = h / 2}
  else
    local cb = proto.collision_box
    box = {l = cb.left_top.x, t = cb.left_top.y, r = cb.right_bottom.x, b = cb.right_bottom.y}
  end
  if dir % 4 == 0 then box = G.rot_box(box, dir) end
  return {
    l = box.l + e.position.x, t = box.t + e.position.y,
    r = box.r + e.position.x, b = box.b + e.position.y,
  }
end

function G.bounds(ents, tiles, mode)
  local acc
  for _, e in pairs(ents or {}) do acc = union(acc, G.entity_box(e, mode)) end
  for _, t in pairs(tiles or {}) do
    acc = union(acc, {l = t.position.x, t = t.position.y, r = t.position.x + 1, b = t.position.y + 1})
  end
  return acc
end

function G.center(b) return {x = (b.l + b.r) / 2, y = (b.t + b.b) / 2} end

-- Model "round": the rotated bounds centre lands on P, with the translation
-- rounded half-up onto the build grid. ghost = t + R_d(pos).
function G.t_round(bounds, P, d, grid)
  grid = grid or 1
  local c = G.rot(G.center(bounds), d)
  return {
    x = grid * floor((P.x - c.x) / grid + 0.5),
    y = grid * floor((P.y - c.y) / grid + 0.5),
  }
end

-- Simple Recursive Blueprints' transform, re-derived algebraically (not copied):
-- ghost = P + R_d(pos - c) + frac(c_d), c = bounds centre, c_d = c with the axes
-- swapped for east and west. As a translation: t = P - R_d(c) + frac(c_d).
function G.t_srb(bounds, P, d)
  local c = G.center(bounds)
  local cd = (d == 4 or d == 12) and {x = c.y, y = c.x} or c
  local rc = G.rot(c, d)
  return {x = P.x - rc.x + G.frac(cd.x), y = P.y - rc.y + G.frac(cd.y)}
end

-- Absolute snapping model: grid lines at rel + k*g' in world space, where g' is
-- the grid with axes swapped for east/west. The blueprint origin goes to the
-- top-left of the cell holding P, plus a per-direction shift that brings the
-- rotated cell [0,gx]x[0,gy] back onto that cell.
function G.t_abs(P, d, grid, rel)
  local gx, gy = grid.x, grid.y
  if d == 4 or d == 12 then gx, gy = gy, gx end
  local tl = {x = rel.x + gx * floor((P.x - rel.x) / gx), y = rel.y + gy * floor((P.y - rel.y) / gy)}
  local shift = ({[0] = {x = 0, y = 0}, [4] = {x = gx, y = 0}, [8] = {x = gx, y = gy}, [12] = {x = 0, y = gy}})[d]
  return G.add(tl, shift)
end

return G
