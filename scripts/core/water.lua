-- Water under a copy (DESIGN.md D52): any floor with the water_tile layer,
-- so lava, oil and ammonia oceans, Gleba's wetlands and space too. A copy
-- stands there only where its design's own tiles make it ground, or where
-- its project superforces (plan.cover_water): the engine then lays each
-- floor's cover tile (landfill, foundation, ice platform, platform
-- foundation) where it keeps the copy off, as a superforced paste does, and
-- the materials gate counts those tiles' items with the design's own
-- (plan.cover). Measured on 2.1.23, base and Space Age: forced and
-- superforced builds cover alike, once the force has an enabled recipe for
-- the cover tile's item that is not hidden (the technology alone does not
-- do it). They cover where a part's collision mask meets the floor, the
-- tiles of its collision box only, and where the floor fails one of its
-- tile rules (an offshore pump's own tile, a rail ramp's foot), if the
-- cover would not; and under a design tile that can go on the cover, which
-- stacks on it. Without the recipe they place nothing there. A forced
-- check that passes over water means the engine covers it; tiles have no
-- such check, so their recipe is looked up.

local const = require("scripts.const")
local geometry = require("scripts.core.geometry")

local water = {}

local REASON = const.REASON

-- A footprint holding at most this many tiles per entity part is looked
-- over for water once; a sparser one costs less looked under part by part
-- (measured: one look 1 µs, plus 5 ns a tile looked over).
local DENSE = 200

local function overlap(a, b)
  for layer in pairs(a) do
    if b[layer] then return true end
  end
  return false
end

-- Per session (prototypes cannot change while the script runs; rebuilt on
-- every load): per entity name the areas where a floor may keep it off,
-- per floor name its layers and its cover ({item, count, layers, open:
-- whether a tile may go on it}, false when none), per item the recipes
-- that make it and are not hidden.
local parts, floors, makers = {}, {}, {}

-- A part's areas, each {turned (geometry.turned), keeps_off(layers)}: its
-- collision box, where its own mask meets the floor, and each tile rule's
-- area, where the floor fails the rule (required layers: any one of them).
-- false when there is none (a marker) or its prototype is gone.
local function part_of(name)
  local known = parts[name]
  if known ~= nil then return known end
  local proto = prototypes.entity[name]
  known = false
  if proto then
    local mask, areas = proto.collision_mask.layers, {}
    if next(mask) then
      local function meets(layers) return overlap(mask, layers) end
      areas[1] = { turned = geometry.turned(proto.collision_box), keeps_off = meets }
    end
    for _, r in ipairs(proto.tile_buildability_rules or {}) do
      local required, colliding = r.required_tiles.layers, r.colliding_tiles.layers
      areas[#areas + 1] = { turned = geometry.turned(r.area), keeps_off = function(layers)
        return overlap(colliding, layers) or (next(required) ~= nil and not overlap(required, layers))
      end }
    end
    known = #areas > 0 and areas
  end
  parts[name] = known
  return known
end

local function floor_of(name)
  local known = floors[name]
  if known then return known end
  local proto = prototypes.tile[name]
  local cover = proto.default_cover_tile
  local items = cover and cover.items_to_place_this
  local item = items and items[1]
  known = { layers = proto.collision_mask.layers, cover = false }
  if item then
    known.cover = { item = item.name, count = item.count or 1, layers = cover.collision_mask.layers, open = cover.allows_being_covered }
  end
  floors[name] = known
  return known
end

local function makers_of(item)
  local list = makers[item]
  if not list then
    list = {}
    for name in pairs(prototypes.get_recipe_filtered {
      { filter = "has-product-item", elem_filters = { { filter = "name", name = item } } },
      { filter = "hidden", invert = true, mode = "and" },
    }) do list[#list + 1] = name end
    makers[item] = list
  end
  return list
end

-- Calls fn(box, keeps_off) for each of the part's areas placed at (x, y)
-- facing `direction`, until fn returns true; whether it did.
local function each_area(areas, x, y, direction, fn)
  for _, area in ipairs(areas) do
    if fn(geometry.placed(area.turned, x, y, direction), area.keeps_off) then return true end
  end
  return false
end

-- What one check knows of water: the design's ground tiles (the tile check
-- fills them in), the cover noted by tile, and what it looked at.
function water.context(surface, force, plan)
  return {
    surface = surface, force = force, plan = plan, ground = {}, covered = {}, cover = {}, unlocked = {},
    tiles = 0, looks = 0,
  }
end

-- One filter for every look, its area set before each.
local LOOK = { area = { left_top = {}, right_bottom = {} }, collision_mask = "water_tile" }

local function set_area(box)
  local a = LOOK.area
  a.left_top.x, a.left_top.y, a.right_bottom.x, a.right_bottom.y = box.left, box.top, box.right, box.bottom
end

-- Whether the footprint may hold water: looked over once when dense (see
-- DENSE); a sparse one counts as wet, each part looked under on its own.
local function maybe_wet(w)
  if w.wet ~= nil then return w.wet end
  local plan = w.plan
  local size = geometry.box_size(plan.footprint)
  local tiles = size.x * size.y
  w.wet = true
  if tiles <= DENSE * math.max(1, #plan.prepared.placements) then
    set_area(plan.footprint)
    LOOK.limit = 1
    w.wet, w.tiles = w.surface.count_tiles_filtered(LOOK) > 0, tiles
  end
  return w.wet
end

-- The water under the box that keeps the part off: whether there is any,
-- and the tiles of it the design's own tiles do not make ground. A box that
-- holds water costs a second look's worth.
local function blocking(w, box, keeps_off)
  set_area(box)
  LOOK.limit = nil
  local found = w.surface.find_tiles_filtered(LOOK)
  w.looks = w.looks + (#found > 0 and 2 or 1)
  local open, any = {}, false
  for _, tile in ipairs(found) do
    if keeps_off(floor_of(tile.name).layers) then
      any = true
      local p = tile.position
      if not w.ground[geometry.tile_key(p.x, p.y)] then open[#open + 1] = tile end
    end
  end
  return any, open
end

local function any_enabled(force, recipes)
  for _, name in ipairs(recipes) do
    if force.recipes[name].enabled then return true end
  end
  return false
end

-- Whether the force can make the cover's item, so that the engine lays it:
-- an enabled recipe makes it and is not hidden (measured), per check.
local function unlocked(w, cover)
  local known = w.unlocked[cover.item]
  if known == nil then
    known = any_enabled(w.force, makers_of(cover.item))
    w.unlocked[cover.item] = known
  end
  return known
end

-- Notes the cover the engine lays on the floor tile at (x, y), once per
-- tile.
local function note(w, cover, x, y)
  local key = geometry.tile_key(x, y)
  if w.covered[key] then return end
  w.covered[key] = true
  w.cover[cover.item] = (w.cover[cover.item] or 0) + cover.count
end

-- Notes the cover on each tile, which the plan must allow and which must
-- not keep the part off itself: whether every tile gets it. `by_recipe`: the
-- force's recipes say whether the engine lays it, where no forced check
-- passed to say so.
local function cover_all(w, tiles, keeps_off, by_recipe)
  if not w.plan.cover_water then return false end
  for _, tile in ipairs(tiles) do
    local cover = floor_of(tile.name).cover
    if not cover or keeps_off(cover.layers) or (by_recipe and not unlocked(w, cover)) then return false end
    local p = tile.position
    note(w, cover, p.x, p.y)
  end
  return true
end

-- An entity part the forced check let through: water that keeps it off and
-- that its design does not make ground is what the engine would cover. nil
-- when the plan may have it covered (noted), else REASON.water.
function water.part(w, name, x, y, direction)
  local areas = part_of(name)
  if not (areas and maybe_wet(w)) then return nil end
  local stopped = each_area(areas, x, y, direction, function(box, keeps_off)
    local _, open = blocking(w, box, keeps_off)
    return #open > 0 and not cover_all(w, open, keeps_off, false)
  end)
  if stopped then return REASON.water end
end

-- What the forced check refused a part for, when water keeps it off:
-- water.GROUND when the design's own tiles make all of it ground (laid
-- first, so the part goes down), REASON.water when it stays water, nil when
-- there is none or the engine covers the rest for a superforced plan
-- (noted), and the part is judged by what else is there.
water.GROUND = "ground"

function water.blocked(w, name, x, y, direction)
  local areas = part_of(name)
  if not (areas and maybe_wet(w)) then return nil end
  local found, opened = false, false
  local stopped = each_area(areas, x, y, direction, function(box, keeps_off)
    local any, open = blocking(w, box, keeps_off)
    found, opened = found or any, opened or #open > 0
    return #open > 0 and not cover_all(w, open, keeps_off, true)
  end)
  if stopped then return REASON.water end
  if found and not opened then return water.GROUND end
end

-- A design tile that is not ground, refused on the floor tile `current` at
-- (x, y), its item kept off tiles with any of the layers in `condition`:
-- true when the engine covers that tile first, which the plan allows, the
-- force can, and the design tile can go on (noted).
function water.tile(w, current, x, y, condition)
  local cover = w.plan.cover_water and floor_of(current.name).cover
  if not (cover and cover.open and unlocked(w, cover)) then return false end
  for _, layer in ipairs(condition) do
    if cover.layers[layer] then return false end
  end
  note(w, cover, x, y)
  return true
end

-- What the check noted: the cover's items ({[item] = count}, nil when
-- none), the footprint tiles it looked over and its looks under parts
-- (work.lua charges both).
function water.noted(w)
  return next(w.cover) and w.cover or nil, w.tiles, w.looks
end

-- The tile a copy lays where a ghost of tile `name` came out, `was` the
-- one already recorded there (or nil): over water the engine stacks its
-- cover (a foundation tile) under a design tile, and the one on top is
-- what stands there once built.
function water.top_tile(was, name)
  if was and prototypes.tile[name].is_foundation then return was end
  return name
end

return water
