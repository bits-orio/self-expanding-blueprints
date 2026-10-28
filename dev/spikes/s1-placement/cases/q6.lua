-- Q6 obstacles and build modes, and whether can_place_entity predicts forced mode.
local fmt = require("lib.fmt")
local G = require("lib.geom")
local B = require("lib.bp")
local D = require("lib.designs")
local Q = {id = "Q6"}

local MARKER = "seb-spike-marker"
local MODES = {
  {name = "normal", mode = defines.build_mode.normal},
  {name = "forced", mode = defines.build_mode.forced},
  {name = "superforced", mode = defines.build_mode.superforced},
}

local function nauvis() return game.surfaces.nauvis end

local function ce(params)
  params.force = params.force or "player"
  return nauvis().create_entity(params)
end

local function set_cliff_explosives(on)
  game.forces.player.technologies["cliff-explosives"].researched = on
end

local OBSTACLES = {
  {id = "none", make = function() return nil end},
  {id = "tree", make = function(W) return ce({name = "tree-01", position = W, force = "neutral"}) end},
  {id = "rock", make = function(W) return ce({name = "big-rock", position = W, force = "neutral"}) end},
  {id = "water", make = function(W)
    nauvis().set_tiles({{name = "water", position = {x = math.floor(W.x), y = math.floor(W.y)}}})
    return nil
  end},
  {id = "own-building", make = function(W) return ce({name = "wooden-chest", position = W}) end},
  {id = "other-force-building", make = function(W) return ce({name = "wooden-chest", position = W, force = "seb-other"}) end},
  {id = "enemy-building", make = function(W) return ce({name = "wooden-chest", position = W, force = "enemy"}) end},
  {id = "neutral-building", make = function(W) return ce({name = "wooden-chest", position = W, force = "neutral"}) end},
  {id = "own-ghost", make = function(W) return ce({name = "entity-ghost", inner_name = "wooden-chest", position = W}) end},
  {id = "item-on-ground", make = function(W)
    return ce({name = "item-on-ground", position = W, stack = {name = "iron-plate", count = 1}, force = "neutral"}) end},
  {id = "cliff", make = function(W) return ce({name = "cliff", position = W, cliff_orientation = "west-to-east", force = "neutral"}) end},
  {id = "cliff+explosives-researched", pre = function() set_cliff_explosives(true) end,
    post = function() set_cliff_explosives(false) end,
    make = function(W) return ce({name = "cliff", position = W, cliff_orientation = "west-to-east", force = "neutral"}) end},
}

-- Expected world placement of every design entity, from a clean stamp.
local function calibrate(bp, P0)
  local rec = B.stamp(bp, nauvis(), P0, 0, {radius = 8})
  local cal = {}
  for _, g in pairs(rec.ghosts) do
    if g.kind == "e" then cal[g.i] = {off = G.sub(g.pos, P0), dir = g.dir, name = g.name} end
  end
  return cal
end

local function predict(cal, P)
  local cpF, cpN, cpG = {}, {}, {}
  local s = nauvis()
  for i, c in ipairs(cal) do
    local args = {name = c.name, position = G.add(P, c.off), direction = c.dir, force = "player",
      build_check_type = defines.build_check_type.blueprint_ghost, forced = true}
    cpF[i] = s.can_place_entity(args)
    args.forced = false
    cpN[i] = s.can_place_entity(args)
    cpG[i] = s.can_place_entity({name = "entity-ghost", inner_name = c.name, position = G.add(P, c.off),
      direction = c.dir, force = "player", build_check_type = defines.build_check_type.blueprint_ghost, forced = true})
  end
  return cpF, cpN, cpG
end

local function built_list(cal, P)
  local out = {}
  for i, c in ipairs(cal) do
    local W = G.add(P, c.off)
    out[i] = nauvis().count_entities_filtered({area = {{W.x - 0.1, W.y - 0.1}, {W.x + 0.1, W.y + 0.1}},
      name = "entity-ghost", ghost_name = c.name}) > 0
  end
  return out
end

local function names_of(list)
  local t = {}
  for _, e in pairs(list) do t[#t + 1] = e.name .. (e.type == "entity-ghost" and ("(" .. e.ghost_name .. ")") or "") end
  table.sort(t)
  return table.concat(t, ",")
end

local function same(a, b)
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end

local function all_true(a)
  for i = 1, #a do if not a[i] then return false end end
  return true
end

local function run_case(bp, cal, obstacle, mode, P)
  local W = G.add(P, cal[1].off) -- the assembler's centre
  if obstacle.pre then obstacle.pre() end
  local made = obstacle.make(W)
  local made_desc = made and (made.name .. "@" .. fmt.p(made.position) .. " box=" ..
    fmt.p(made.bounding_box.left_top) .. ".." .. fmt.p(made.bounding_box.right_bottom)) or "-"
  local cpF, cpN, cpG = predict(cal, P)
  local area = B.area(P, 6)
  local ghosts_before = nauvis().count_entities_filtered({area = area, type = "entity-ghost"})
  local ret = bp.stack.build_blueprint({surface = nauvis(), force = "player", position = P, direction = 0,
    build_mode = mode.mode, raise_built = true, skip_fog_of_war = false})
  local built = built_list(cal, P)
  local decon = nauvis().find_entities_filtered({area = area, to_be_deconstructed = true})
  local tile_ghosts = nauvis().find_entities_filtered({area = area, type = "tile-ghost"})
  local ghosts_after = nauvis().count_entities_filtered({area = area, type = "entity-ghost"})
  local verdict_ok, rule
  if mode.name == "forced" then
    verdict_ok, rule = same(cpF, built), "cp_forced==built"
  elseif mode.name == "normal" then
    verdict_ok, rule = (all_true(cpN) and all_true(built)) or (not all_true(cpN) and #ret == 0), "all(cp_normal)?all:none"
  else
    verdict_ok, rule = true, "info-only"
  end
  fmt.verdict("Q6 " .. obstacle.id .. " mode=" .. mode.name, verdict_ok, "rule=" .. rule, "n_ret=" .. #ret,
    "built=" .. fmt.bits(built), "cp_forced=" .. fmt.bits(cpF), "cp_normal=" .. fmt.bits(cpN),
    "cp_ghost_forced=" .. fmt.bits(cpG), "entity_ghosts=" .. ghosts_before .. "->" .. ghosts_after,
    "decon=" .. names_of(decon), "tile_ghosts=" .. names_of(tile_ghosts),
    "obstacle_after=" .. (made and (made.valid and ("valid,decon=" .. tostring(made.to_be_deconstructed())) or "gone") or "-"),
    "obstacle=" .. made_desc)
  if obstacle.post then obstacle.post() end
end

-- Mining drills: ghost placement needs a resource under the drill.
local function drill_case()
  local bp = B.new({id = "drill", entities = {D.ent("electric-mining-drill", 0.5, 0.5, 0)}})
  for _, with_ore in ipairs({false, true}) do
    local P = with_ore and {x = 1280, y = 100} or {x = 1260, y = 100}
    local W = {x = P.x + 0.5, y = P.y + 0.5}
    if with_ore then
      for dx = -1, 1 do
        for dy = -1, 1 do
          nauvis().create_entity({name = "iron-ore", position = {W.x + dx, W.y + dy}, amount = 1000})
        end
      end
    end
    local cpF = nauvis().can_place_entity({name = "electric-mining-drill", position = W, direction = 0, force = "player",
      build_check_type = defines.build_check_type.blueprint_ghost, forced = true})
    local ret = bp.stack.build_blueprint({surface = nauvis(), force = "player", position = P, direction = 0,
      build_mode = defines.build_mode.forced, raise_built = true})
    fmt.verdict("Q6.drill ore=" .. tostring(with_ore), cpF == (#ret == 1), "n_ret=" .. #ret,
      "cp_forced=" .. tostring(cpF))
  end
  bp.inv.destroy()
end

-- Tiles over water: plain tiles, and landfill carrying an entity.
local function water_area(P, r)
  local t = {}
  for x = P.x - r, P.x + r - 1 do
    for y = P.y - r, P.y + r - 1 do t[#t + 1] = {name = "water", position = {x = x, y = y}} end
  end
  nauvis().set_tiles(t)
end

local function tiles_case()
  local land = {}
  for x = -1, 1 do
    for y = -1, 1 do land[#land + 1] = {name = "landfill", position = {x = x, y = y}} end
  end
  local specs = {
    {id = "stone-on-water", tiles = D.g2.tiles, entities = {D.ent("wooden-chest", 3.5, 0.5)}},
    {id = "landfill+chest-on-water", tiles = land, entities = {D.ent("wooden-chest", 0.5, 0.5)}},
  }
  local x = 1180
  for _, spec in ipairs(specs) do
    local bp = B.new(spec)
    for _, mode in ipairs(MODES) do
      x = x + 10
      local P = {x = x, y = 110}
      water_area(P, 3)
      local chest = G.add(P, {x = 0.5, y = 0.5})
      if spec.id == "stone-on-water" then chest = G.add(P, {x = 1.5, y = -0.5}) end
      local cp = nauvis().can_place_entity({name = "wooden-chest", position = chest, force = "player",
        build_check_type = defines.build_check_type.blueprint_ghost, forced = true})
      local rec = B.stamp(bp, nauvis(), P, 0, {mode = mode.mode, keep = true, radius = 5})
      local nt, ne, tnames = 0, 0, {}
      for _, g in pairs(rec.ghosts) do
        if g.kind == "t" then nt = nt + 1 tnames[g.name] = (tnames[g.name] or 0) + 1 else ne = ne + 1 end
      end
      fmt.out("Q6.tiles " .. spec.id .. " mode=" .. mode.name, "n_ret=" .. rec.n_ret, "tile_ghosts=" .. nt .. "/" .. #bp.tiles,
        "entity_ghosts=" .. ne .. "/" .. #bp.ent_list, "tile_names=" .. fmt.line(tnames),
        "cp_forced_chest_before=" .. tostring(cp), "chest_world=" .. fmt.p(chest))
    end
    bp.inv.destroy()
  end
end

function Q.run()
  tiles_case()
  local spec = D.copy_spec(D.a, "a+m")
  spec.entities[#spec.entities + 1] = D.ent(MARKER, 0.5, 0.5, 0)
  local bp = B.new(spec)
  local cal = calibrate(bp, {x = 1100, y = -100})
  local parts = {}
  for i, c in ipairs(cal) do parts[#parts + 1] = i .. ":" .. c.name .. "@" .. fmt.p(c.off) end
  fmt.out("Q6.design a+m (entity order for the bit strings) " .. table.concat(parts, " "))
  local col = 0
  for _, obstacle in ipairs(OBSTACLES) do
    col = col + 1
    for row, mode in ipairs(MODES) do
      run_case(bp, cal, obstacle, mode, {x = 1090 + col * 16, y = -60 + row * 30})
    end
  end
  drill_case()
  bp.inv.destroy()
end

return Q
