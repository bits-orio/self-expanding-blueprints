-- Rigid-transform and model checks for one stamp record.
local G = require("lib.geom")
local fmt = require("lib.fmt")
local A = {}

local function tile_centers(bp, d)
  local list = {}
  for _, t in pairs(bp.tiles) do
    list[#list + 1] = {name = t.name, pos = G.rot({x = t.position.x + 0.5, y = t.position.y + 0.5}, d)}
  end
  return list
end

local function tile_set(list, t)
  local keys = {}
  for _, e in pairs(list) do
    keys[#keys + 1] = e.name .. "@" .. fmt.p(G.add(e.pos, t))
  end
  table.sort(keys)
  return table.concat(keys, ";")
end

local function ghost_tile_set(rec)
  local keys = {}
  for _, g in pairs(rec.ghosts) do
    if g.kind == "t" then keys[#keys + 1] = g.name .. "@" .. fmt.p(g.pos) end
  end
  table.sort(keys)
  return table.concat(keys, ";")
end

-- Translation t with ghost = t + R_d(blueprint position), from entity ghosts if
-- any, else from tiles. Returns {t, rigid, maxdev, dir_bad, missing, extra}.
function A.rigid(bp, rec)
  local d = rec.d
  local t, maxdev, n = nil, 0, 0
  local dir_bad, dir_opposite, seen = {}, {}, {}
  local dir_exact, dir_fixed = 0, 0
  for _, g in pairs(rec.ghosts) do
    if g.kind == "e" then
      local e = g.i and bp.ents[g.i]
      if e then
        seen[g.i] = true
        local r = G.rot(e.position, d)
        local ti = {x = g.pos.x - r.x, y = g.pos.y - r.y}
        if not t then
          t = ti
        else
          maxdev = math.max(maxdev, math.abs(ti.x - t.x), math.abs(ti.y - t.y))
        end
        local expect = ((e.direction or 0) + d) % 16
        local desc = e.name .. "(" .. (e.direction or 0) .. "+" .. d .. "=" .. expect .. " got " .. g.dir .. ")"
        if g.dir == expect then
          dir_exact = dir_exact + 1
        elseif not prototypes.entity[e.name].supports_direction and g.dir == 0 then
          dir_fixed = dir_fixed + 1
        elseif (g.dir - expect) % 16 == 8 then
          dir_opposite[#dir_opposite + 1] = desc
        else
          dir_bad[#dir_bad + 1] = desc
        end
        n = n + 1
      end
    end
  end
  local missing, missing_names = 0, {}
  for i, e in pairs(bp.ents) do
    if not seen[i] then
      missing = missing + 1
      missing_names[#missing_names + 1] = e.name
    end
  end
  local tiles = tile_centers(bp, d)
  local tiles_ok = true
  if #tiles > 0 then
    if not t then
      -- derive t from the lexicographic minimum of tile positions
      local gmin, bmin
      for _, g in pairs(rec.ghosts) do
        if g.kind == "t" and (not gmin or g.pos.x < gmin.x or (g.pos.x == gmin.x and g.pos.y < gmin.y)) then gmin = g.pos end
      end
      for _, e in pairs(tiles) do
        if not bmin or e.pos.x < bmin.x or (e.pos.x == bmin.x and e.pos.y < bmin.y) then bmin = e.pos end
      end
      if gmin and bmin then t = G.sub(gmin, bmin) end
    end
    tiles_ok = t ~= nil and tile_set(tiles, t) == ghost_tile_set(rec)
  end
  return {
    t = t, n = n, maxdev = maxdev, rigid = (t ~= nil and maxdev < 1e-6 and tiles_ok),
    tiles_ok = tiles_ok, dir_bad = dir_bad, dir_opposite = dir_opposite, dir_exact = dir_exact,
    dir_fixed = dir_fixed, missing = missing, missing_names = missing_names,
  }
end

-- Predicted translation under each model, given the blueprint's stored contents.
function A.models(bp, P, d, grid)
  local tb = G.bounds(bp.ent_list, bp.tiles, "tile")
  local cb = G.bounds(bp.ent_list, bp.tiles, "coll")
  return {
    bounds_tile = tb,
    bounds_coll = cb,
    round_tile = tb and G.t_round(tb, P, d, grid),
    round_coll = cb and G.t_round(cb, P, d, grid),
    srb = tb and G.t_srb(tb, P, d),
  }
end

function A.match(t, pred)
  return t ~= nil and pred ~= nil and G.same(t, pred)
end

return A
