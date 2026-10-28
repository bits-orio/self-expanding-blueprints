-- Ore sensors: markers that make a design's copies open their sockets only
-- once the ore they watch has run out, instead of as soon as the copy is
-- built (DESIGN.md, "Depletion"). What a sensor watches, in blueprint
-- coordinates:
--   with a radius signal R:   the square of 2R + 1 tiles around it
--   on a mining drill:        that drill's whole mining area
--   anywhere else:            its own tile
-- So a player who wants growth to go on before a drill's whole area is
-- mined out puts a sensor with a small R on the part that matters.

local geometry = require("scripts.core.geometry")

local sensors = {}

-- A larger R is a typo, and would watch (and index) millions of tiles.
local MAX_RADIUS = 64

local function square(p, r)
  return geometry.tile_box(geometry.box(p.x - r - 0.5, p.y - r - 0.5, p.x + r + 0.5, p.y + r + 0.5))
end

-- The first mining drill of the design on each whole tile it covers, once
-- for the design: asking every sensor to walk every part would be sensors
-- times parts, in the tick a design is registered.
local function drills_by_tile(buildable, entity_box)
  local by_tile, drill_proto = {}, {}
  for _, e in ipairs(buildable) do
    local proto = drill_proto[e.name]
    if proto == nil then
      proto = prototypes.entity[e.name]
      proto = proto and proto.type == "mining-drill" and proto or false
      drill_proto[e.name] = proto
    end
    if proto then
      local box = entity_box(e)
      for x = box.left, box.right - 1 do
        for y = box.top, box.bottom - 1 do
          local key = geometry.tile_key(x, y)
          if not by_tile[key] then by_tile[key] = { e, proto } end
        end
      end
    end
  end
  return by_tile
end

local function drill_under(position, by_tile)
  local found = by_tile[geometry.tile_key(position.x, position.y)]
  if found then return found[1], found[2] end
end

-- The area each sensor watches, and for a sensor on a drill the resource
-- categories that drill mines (ore it cannot mine is not "left" for it).
-- `entity_box(e)` is the tile box of a blueprint entity (prepare.lua).
function sensors.areas(list, buildable, entity_box)
  local areas, categories = {}, {}
  local by_tile = #list > 0 and drills_by_tile(buildable, entity_box) or nil
  for i, s in ipairs(list) do
    local drill, proto = nil, nil
    if not s.radius then drill, proto = drill_under(s.position, by_tile) end
    if drill then
      local p, r = drill.position, proto.mining_drill_radius
      areas[i] = geometry.tile_box(geometry.box(p.x - r, p.y - r, p.x + r, p.y + r))
      categories[i] = proto.resource_categories
    else
      areas[i] = square(s.position, math.min(MAX_RADIUS, math.max(0, math.floor(s.radius or 0))))
    end
  end
  return areas, categories
end

return sensors
