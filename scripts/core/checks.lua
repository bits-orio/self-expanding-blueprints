-- Checks before a stamp, so stamps are all or nothing and a closed socket
-- can say what stopped it and where. They look under the copy's parts, never
-- at its whole footprint, so what one costs follows its parts, its Keep
-- clear tiles and the cliffs it meets (water is looked for over a footprint
-- only where it holds few tiles a part). Trees and rocks are not obstacles:
-- forced build mode marks them for deconstruction. The entity check is
-- LuaSurface.can_place_entity with the entity's own name, build_check_type
-- blueprint_ghost and forced = true, which predicts forced mode exactly
-- (spike S1). The API has no tile check, so tiles get their own. Cliffs:
-- cliffs.lua. Water, which the forced check lets through once the force
-- can make landfill: water.lua.

local const = require("scripts.const")
local geometry = require("scripts.core.geometry")
local ltr = require("scripts.compat.ltr")
local clearance = require("scripts.core.clearance")
local placement = require("scripts.core.placement")
local under = require("scripts.core.under")
local cliffs = require("scripts.core.cliffs")
local water = require("scripts.core.water")

local checks = {}

local REASON = const.REASON

local function uncharted(cx, cy)
  return { kind = "closed", reason = REASON.uncharted, position = geometry.chunk_center(cx, cy) }
end

-- Charted and generated chunks under the footprint. Returns nil, a closed
-- verdict (uncharted) or a gate (chunks still generating, now requested).
-- Only rules.generate has the game make map (D43): a remote caller's real
-- growth or stamp off charted land. Anything a player starts, and every
-- plan, takes a chunk that does not exist yet for uncharted land.
function checks.terrain(surface, force, footprint, rules)
  if surface.platform then return nil end
  local verdict
  geometry.each_chunk(footprint, function(cx, cy)
    if verdict and verdict.kind == "closed" then return end
    local chunk = { x = cx, y = cy }
    if rules.charted_only and not force.is_chunk_charted(surface, chunk) then
      verdict = uncharted(cx, cy)
    elseif not surface.is_chunk_generated(chunk) then
      if not rules.generate then
        verdict = uncharted(cx, cy)
      else
        surface.request_to_generate_chunks(geometry.chunk_center(cx, cy), 0)
        verdict = verdict or { kind = "gate", reason = REASON.chunks }
      end
    end
  end)
  return verdict
end

-- Per tile name, constant for the session (prototypes cannot change while the
-- script runs, and this table is rebuilt on every load).
local tile_info = {}

local function info_of(name)
  local info = tile_info[name]
  if info then return info end
  local proto = prototypes.tile[name]
  info = { makes_ground = not proto.collision_mask.layers.water_tile, layers = {} }
  local items = proto.items_to_place_this
  local item = items and items[1] and prototypes.item[items[1].name]
  local rule = item and item.place_as_tile_result
  if rule and not rule.invert and not (rule.tile_condition and #rule.tile_condition > 0) then
    for layer in pairs(rule.condition.layers or {}) do info.layers[#info.layers + 1] = layer end
  end
  tile_info[name] = info
  return info
end

-- Whether the item that places the tile refuses the tile already there. Only
-- plain conditions are judged; inverted and tile-list conditions are left to
-- the engine.
local function tile_refused(info, current)
  for _, layer in ipairs(info.layers) do
    if current.collides_with(layer) then return true end
  end
  return false
end

-- The design's tiles: the first one that cannot go down, with its reason
-- and position. The world tiles they turn into ground go into w.ground. One
-- that is not ground goes on water only where the engine covers it first
-- with a floor it can go on (water.lua).
local function check_tiles(surface, plan, w)
  local reason, where
  placement.each_tile(plan.prepared, plan.position, plan.direction, function(tile, x, y)
    local info = info_of(tile.name)
    local current = surface.get_tile(x, y)
    if current.name ~= tile.name and tile_refused(info, current) then
      local wet = current.collides_with("water_tile")
      if not (wet and water.tile(w, current, x, y, info.layers)) then
        reason, where = wet and REASON.water or REASON.building, { x = x + 0.5, y = y + 0.5 }
        return true
      end
    end
    if info.makes_ground then w.ground[geometry.tile_key(x, y)] = true end
  end)
  return reason, where
end

-- The cliffs under a part, noted (cliffs.lua): nil, or a cliff that stops
-- the plan and where. One count first, as cliffs are rare and this runs for
-- many parts.
local function cliffs_under(c, name, x, y, direction)
  local part = under.part_box(name, x, y, direction)
  if not under.any(c.surface, part, "cliff") then return nil end
  return cliffs.under(c.surface, c.force, c.plan, { part })
end

-- Names what stops a part at `at` from being placed, with the cliff's
-- position for a cliff; nil when only water that the design's own landfill
-- covers is in the way. Water the engine covers for a superforced plan is
-- noted (water.lua) and the part judged by what else is there. A cliff the
-- force may blow up is noted on the plan instead (cliffs.lua); rails reach
-- past their collision box (under.part_box).
local function classify(c, name, at, direction)
  local surface = c.surface
  local wet = water.blocked(c.water, name, at.x, at.y, direction)
  if wet == water.GROUND then return nil end
  if wet then return wet end
  local area = geometry.area(under.collision_box(name, at.x, at.y, direction))
  local reason, where = cliffs_under(c, name, at.x, at.y, direction)
  if reason then return reason, where end
  if ltr.blocks(surface, area) then return REASON.held_land end
  if prototypes.entity[name].type == "mining-drill"
    and surface.count_entities_filtered { area = area, type = "resource", limit = 1 } == 0 then
    return REASON.no_resource
  end
  return REASON.building
end

local function placeable(c, forced)
  c.args.forced = forced
  return c.surface.can_place_entity(c.args)
end

-- What stands in the part's way: nil when it fits with nothing to note,
-- true when only what forced mode clears does (trees, rocks and cliffs the
-- force may blow up, whose cliffs are noted), false when anything else does.
-- With cliff explosives the forced check passes over cliffs, so the plain
-- check says whether anything is there at all: first, unless superforced,
-- where most parts stand over the force's own buildings.
local function clearable(c)
  if not c.removable then return placeable(c, true) and nil end
  if not c.plan.superforce then
    if placeable(c, false) then return nil end
    return placeable(c, true)
  end
  if not placeable(c, true) then return false end
  return not placeable(c, false) or nil
end

-- A part the forced check refused: why, and where; nil when the build
-- clears what is there anyway.
local function refused_part(c, name, x, y, facing)
  local why, where = classify(c, name, c.args.position, facing)
  -- Superforced, a building in the way is marked for removal instead.
  if c.plan.superforce and why == REASON.building then return nil end
  if why then return why, where or { x = x, y = y } end
end

-- One entity part: nil, or why it cannot be placed and where. Water under
-- a part the forced check lets through is the engine's to cover (water.lua),
-- and the cliffs under a part that only meets what forced mode clears are
-- noted. A part with anything else in its way is counted (c.met): what is
-- there is looked up, which costs about five free parts' checks (work.lua
-- charges it).
local function check_part(c, e, x, y, facing)
  local args = c.args
  args.position.x, args.position.y, args.name, args.direction = x, y, e.name, facing
  local only_clearable = clearable(c)
  if only_clearable ~= false and water.part(c.water, e.name, x, y, facing) then
    return REASON.water, { x = x, y = y }
  end
  if only_clearable == nil then return nil end
  c.met = c.met + 1
  if not only_clearable then return refused_part(c, e.name, x, y, facing) end
  local why, where = cliffs_under(c, e.name, x, y, facing)
  if why then return why, where or { x = x, y = y } end
end

local function check_entities(surface, force, plan, w)
  local c = {
    surface = surface, force = force, plan = plan, water = w, removable = force.cliff_deconstruction_enabled, met = 0,
    args = {
      name = "", position = { x = 0, y = 0 }, direction = 0, force = force,
      build_check_type = defines.build_check_type.blueprint_ghost, forced = true,
    },
  }
  local reason, where
  placement.each_part(plan.prepared, plan.position, plan.direction, function(e, x, y, facing)
    reason, where = check_part(c, e, x, y, facing)
    return reason ~= nil
  end)
  plan.in_way = c.met
  return reason, where
end

local function first_obstacle(surface, force, plan, w)
  local tiles = under.join(under.boxes(plan, "tiles"), under.boxes(plan, "kept"))
  local reason, where = cliffs.under(surface, force, plan, tiles)
  if reason then return reason, where end
  reason, where = check_tiles(surface, plan, w)
  if reason then return reason, where end
  reason, where = check_entities(surface, force, plan, w)
  if reason then return reason, where end
  return clearance.blocked(surface, force, plan)
end

-- nil when every part of the plan can be placed and its Keep clear tiles
-- cleared; else a reason and the map position of the first obstacle. Cliffs
-- under its tiles and Keep clear tiles come first, as a cliff anywhere in the
-- footprint did before; one under an entity part fails that part's check. A
-- plan that passes keeps the cliffs the force will blow up: plan.cliffs =
-- {[explosive] = count} (nil when none) and the cliffs themselves in
-- plan.cliff_entities, for the stamp to order (cliffs.lua); and the items
-- of the landfill the engine lays on water under it, plan.cover = {[item] =
-- count} (nil when none; water.lua). plan.in_way counts the entity parts it
-- found something in the way of, whatever came of it; plan.water_tiles and
-- plan.water_looks what it looked at for water.
function checks.obstacles(surface, force, plan)
  plan.cliffs, plan.cliff_entities, plan.cover, plan.in_way = nil, nil, nil, 0
  local w = water.context(surface, force, plan)
  local reason, where = first_obstacle(surface, force, plan, w)
  local cover
  cover, plan.water_tiles, plan.water_looks = water.noted(w)
  if reason then
    plan.cliffs, plan.cliff_entities = nil, nil
  else
    plan.cover = cover
  end
  return reason, where
end

return checks
