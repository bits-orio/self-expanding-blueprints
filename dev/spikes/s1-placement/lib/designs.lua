-- Design specs used across the questions. Positions are blueprint coordinates.
local Rng = require("lib.rng")
local D = {}

local N, E, S, W = 0, 4, 8, 12

local function ent(name, x, y, dir) return {name = name, position = {x = x, y = y}, direction = dir} end

local function copy_spec(spec, id)
  local c = {id = id, entities = {}, tiles = spec.tiles}
  for i, e in ipairs(spec.entities or {}) do
    c.entities[i] = ent(e.name, e.position.x, e.position.y, e.direction)
  end
  return c
end

local function shifted(spec, id, dx, dy)
  local c = copy_spec(spec, id)
  for _, e in ipairs(c.entities) do e.position = {x = e.position.x + dx, y = e.position.y + dy} end
  return c
end

local function with(spec, id, fields)
  local c = copy_spec(spec, id)
  for k, v in pairs(fields) do c[k] = v end
  return c
end

-- (a) odd 3x3 + 1x1 extras: tile bounds x[-1,4] y[-2,2] (5x4)
D.a = {id = "a", entities = {
  ent("assembling-machine-1", 0.5, 0.5),
  ent("small-electric-pole", 3.5, 0.5),
  ent("small-electric-pole", 0.5, -1.5),
  ent("inserter", 2.5, 1.5, E),
}}
D.a_shift = shifted(D.a, "a_shift", 100, -37)
-- assembler deliberately at an integer position (invalid for a 3x3)
D.a_bad = {id = "a_bad", entities = {ent("assembling-machine-1", 0, 0), ent("small-electric-pole", 3, 0)}}

-- (b) even 2x2 L-shape: x[-1,5] y[-1,3] (6x4)
D.b = {id = "b", entities = {
  ent("accumulator", 0, 0), ent("accumulator", 2, 0), ent("accumulator", 4, 0), ent("accumulator", 0, 2),
}}

-- (c) 5x2 with a rotated non-square splitter
D.c = {id = "c", entities = {
  ent("transport-belt", 0.5, 0.5, E), ent("transport-belt", 1.5, 0.5, E),
  ent("splitter", 3, 0.5, N), ent("transport-belt", 4.5, 0.5, E), ent("transport-belt", 0.5, 1.5, S),
}}

-- (c2) non-square entities in several orientations: x[0,6] y[0,5] (6x5)
D.c2 = {id = "c2", entities = {
  ent("boiler", 1.5, 1, N), ent("pump", 4, 0.5, E), ent("steam-engine", 2.5, 3.5, E),
  ent("wooden-chest", 5.5, 0.5),
}}

-- (e) relative snap, (f) absolute snap, on design (a)
D.e = with(D.a, "e", {snap = {x = 6, y = 6}, absolute = false})
D.e2 = with(D.a, "e2", {snap = {x = 6, y = 4}, absolute = false})
D.e3 = with(D.a_shift, "e3", {snap = {x = 7, y = 3}, absolute = false})
D.f = with(D.a, "f", {snap = {x = 6, y = 6}, absolute = true, rel = {x = 2, y = 1}})
D.f2 = with(D.a, "f2", {snap = {x = 6, y = 4}, absolute = true, rel = {x = 2, y = 1}})
D.f0 = with(D.a, "f0", {snap = {x = 6, y = 6}, absolute = true, rel = {x = 0, y = 0}})
-- same as f2 but with the content moved away from the blueprint origin
D.f3 = with(shifted(D.a, "a13", 13, -7), "f3", {snap = {x = 6, y = 4}, absolute = true, rel = {x = 2, y = 1}})

-- (g) tiles
local function tiles(name, list)
  local out = {}
  for i, p in ipairs(list) do out[i] = {name = name, position = {x = p[1], y = p[2]}} end
  return out
end
D.g1 = {id = "g1", tiles = tiles("stone-path", {{0, 0}, {1, 0}, {2, 0}, {0, 1}})}
D.g2 = {id = "g2", tiles = D.g1.tiles, entities = {ent("wooden-chest", 3.5, 0.5)}}
D.g3 = {id = "g3", tiles = D.g1.tiles, entities = {ent("wooden-chest", 1.5, 0.5)}}
D.g4 = {id = "g4", tiles = tiles("concrete", {{5, 5}, {6, 5}, {5, 6}})}

-- Q4 marker directions, with chests for asymmetry
D.q4 = {id = "q4", entities = {
  ent("wooden-chest", 0.5, 0.5),
  ent("seb-spike-marker", 2.5, 0.5, N), ent("seb-spike-marker", 3.5, 0.5, E),
  ent("seb-spike-marker", 2.5, 1.5, S), ent("seb-spike-marker", 3.5, 1.5, W),
  ent("wooden-chest", 5.5, 2.5),
}}

D.named = {"a", "a_shift", "b", "c", "c2", "g1", "g2", "g3", "g4", "q4"}

-- Random designs (grid-1 entities only; rails are tested separately).
local POOL = {
  {"wooden-chest", false}, {"transport-belt", true}, {"inserter", true}, {"small-electric-pole", false},
  {"constant-combinator", true}, {"arithmetic-combinator", true}, {"pump", true}, {"splitter", true},
  {"accumulator", false}, {"stone-furnace", false}, {"substation", false}, {"assembling-machine-1", false},
  {"electric-mining-drill", true}, {"boiler", true}, {"steam-engine", true}, {"roboport", false},
  {"oil-refinery", true}, {"seb-spike-marker", true}, {"medium-electric-pole", false}, {"lab", false},
  {"radar", false}, {"storage-tank", true}, {"chemical-plant", true}, {"beacon", false},
  {"big-electric-pole", false}, {"heat-exchanger", true}, {"steam-turbine", true}, {"nuclear-reactor", false},
  {"gate", true}, {"stone-wall", false}, {"pipe-to-ground", true}, {"underground-belt", true},
}
D.POOL = POOL

local function try_place(rng, occ, entry)
  local proto = prototypes.entity[entry[1]]
  local dir = entry[2] and rng:pick({N, E, S, W}) or nil
  local w, h = proto.tile_width, proto.tile_height
  if dir == E or dir == W then w, h = h, w end
  local tlx, tly = rng:int(-10, 10), rng:int(-10, 10)
  for x = tlx, tlx + w - 1 do
    for y = tly, tly + h - 1 do
      if occ[x .. "," .. y] then return nil end
    end
  end
  for x = tlx, tlx + w - 1 do
    for y = tly, tly + h - 1 do occ[x .. "," .. y] = true end
  end
  return ent(entry[1], tlx + w / 2, tly + h / 2, dir)
end

function D.random(seed, count)
  local rng = Rng.new(seed)
  local out = {}
  for k = 1, count do
    local occ, list = {}, {}
    local want, tries = rng:int(1, 7), 0
    while #list < want and tries < 300 do
      tries = tries + 1
      local e = try_place(rng, occ, rng:pick(POOL))
      if e then list[#list + 1] = e end
    end
    local spec = {id = "r" .. k, entities = list}
    if rng:int(1, 3) == 1 then
      local seen, tl = {}, {}
      for _ = 1, rng:int(1, 6) do
        local x, y = rng:int(-12, 12), rng:int(-12, 12)
        if not seen[x .. "," .. y] then
          seen[x .. "," .. y] = true
          tl[#tl + 1] = {name = rng:pick({"stone-path", "concrete"}), position = {x = x, y = y}}
        end
      end
      spec.tiles = tl
    end
    out[k] = spec
  end
  return out
end

D.copy_spec = copy_spec
D.with = with
D.ent = ent

return D
