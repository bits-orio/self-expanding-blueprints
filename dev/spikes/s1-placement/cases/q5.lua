-- Q5 overlap: is a marker ghost created on top of real entities, other ghosts,
-- trees, water and cliffs, in each build mode? Is it in the returned array?
local fmt = require("lib.fmt")
local G = require("lib.geom")
local B = require("lib.bp")
local D = require("lib.designs")
local Q = {id = "Q5"}

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

local CASES = {
  {id = "real-own-assembler", make = function(W) return ce({name = "assembling-machine-1", position = W}) end},
  {id = "real-own-chest", make = function(W) return ce({name = "wooden-chest", position = W}) end},
  {id = "real-enemy-chest", make = function(W) return ce({name = "wooden-chest", position = W, force = "enemy"}) end},
  {id = "real-other-force-chest", make = function(W) return ce({name = "wooden-chest", position = W, force = "seb-other"}) end},
  {id = "real-constant-combinator", make = function(W) return ce({name = "constant-combinator", position = W}) end},
  {id = "own-ghost-assembler", make = function(W)
    return ce({name = "entity-ghost", inner_name = "assembling-machine-1", position = W}) end},
  {id = "own-ghost-chest", make = function(W) return ce({name = "entity-ghost", inner_name = "wooden-chest", position = W}) end},
  {id = "marker-ghost-same-dir", make = function(W)
    return ce({name = "entity-ghost", inner_name = MARKER, position = W, direction = 0}) end},
  {id = "marker-ghost-other-dir", make = function(W)
    return ce({name = "entity-ghost", inner_name = MARKER, position = W, direction = 4}) end},
  {id = "real-marker", make = function(W) return ce({name = MARKER, position = W}) end},
  {id = "tree", make = function(W) return ce({name = "tree-01", position = W, force = "neutral"}) end},
  {id = "rock", make = function(W) return ce({name = "big-rock", position = W, force = "neutral"}) end},
  {id = "item-on-ground", make = function(W)
    return ce({name = "item-on-ground", position = W, stack = {name = "iron-plate", count = 1}, force = "neutral"}) end},
  {id = "water", make = function(W)
    nauvis().set_tiles({{name = "water", position = {x = math.floor(W.x), y = math.floor(W.y)}}})
    return nil
  end},
  {id = "cliff", make = function(W) return ce({name = "cliff", position = W, cliff_orientation = "west-to-east", force = "neutral"}) end},
}

local function markers_at(W)
  return nauvis().find_entities_filtered({area = {{W.x - 0.4, W.y - 0.4}, {W.x + 0.4, W.y + 0.4}},
    name = "entity-ghost", ghost_name = MARKER})
end

local function decon_names(P)
  local names = {}
  for _, e in pairs(nauvis().find_entities_filtered({area = B.area(P, 4), to_be_deconstructed = true})) do
    names[#names + 1] = e.name
  end
  table.sort(names)
  return table.concat(names, ",")
end

local function run_case(bp, case, mode, P, off)
  local W = G.add(P, off)
  local obstacle = case.make(W)
  local before = {}
  for _, g in pairs(markers_at(W)) do before[g.unit_number] = g.direction end
  local rec = B.stamp(bp, nauvis(), P, 0, {mode = mode.mode, keep = true, radius = 4})
  local after = markers_at(W)
  local new, in_ret, pre_alive, dirs = 0, false, 0, {}
  for _, g in pairs(after) do
    dirs[#dirs + 1] = g.direction
    if before[g.unit_number] ~= nil then pre_alive = pre_alive + 1 else new = new + 1 end
  end
  for _, g in pairs(rec.ghosts) do
    if g.name == MARKER and g.in_ret then in_ret = true end
  end
  local npre = 0
  for _ in pairs(before) do npre = npre + 1 end
  local obs = "none"
  if obstacle then
    obs = obstacle.valid and ("valid,decon=" .. tostring(obstacle.to_be_deconstructed())) or "gone"
  end
  fmt.out("Q5 " .. case.id .. " mode=" .. mode.name, "new_marker_ghosts=" .. new, "n_ret=" .. rec.n_ret,
    "marker_in_returned=" .. tostring(in_ret), "preexisting_marker_ghosts=" .. npre .. "->alive " .. pre_alive,
    "marker_dirs_at_W=" .. table.concat(dirs, ","), "obstacle=" .. obs, "decon_marks=" .. decon_names(P),
    "W=" .. fmt.p(W))
  return new > 0
end

-- Blueprints whose own entities overlap the marker.
local function in_blueprint_cases()
  local specs = {
    {id = "am", entities = {D.ent("assembling-machine-1", 0.5, 0.5), D.ent(MARKER, 0.5, 0.5, 4)}},
    {id = "cm", entities = {D.ent("wooden-chest", 0.5, 0.5), D.ent(MARKER, 0.5, 0.5, 4)}},
    {id = "mm", entities = {D.ent(MARKER, 0.5, 0.5, 0), D.ent(MARKER, 0.5, 0.5, 4), D.ent("wooden-chest", 2.5, 0.5)}},
  }
  local x = 520
  for _, spec in ipairs(specs) do
    local bp = B.new(spec)
    for _, mode in ipairs(MODES) do
      x = x + 8
      local P = {x = x, y = 80}
      local rec = B.stamp(bp, nauvis(), P, 0, {mode = mode.mode, radius = 4})
      local names, inret = {}, {}
      for _, g in pairs(rec.ghosts) do
        names[#names + 1] = g.name .. "/" .. g.dir .. "@" .. fmt.p(G.sub(g.pos, P))
        inret[#inret + 1] = tostring(g.in_ret)
      end
      fmt.verdict("Q5.inbp " .. spec.id .. " mode=" .. mode.name, rec.n_found == #spec.entities,
        "stored=" .. #bp.ent_list, "n_ret=" .. rec.n_ret, "n_found=" .. rec.n_found,
        "ghosts=" .. table.concat(names, ";"), "in_ret=" .. table.concat(inret, ","))
    end
    bp.inv.destroy()
  end
end

function Q.run()
  local bp = B.new({id = "m1", entities = {D.ent(MARKER, 0.5, 0.5, 0)}})
  local P0 = {x = 520, y = -80}
  local cal = B.stamp(bp, nauvis(), P0, 0, {radius = 4})
  local off = G.sub(cal.ghosts[1].pos, P0)
  fmt.out("Q5.calibration marker off=" .. fmt.p(off), "n_ret=" .. cal.n_ret)
  local col = 0
  for _, case in ipairs(CASES) do
    col = col + 1
    for row, mode in ipairs(MODES) do
      local P = {x = 520 + col * 10, y = -60 + row * 20}
      run_case(bp, case, mode, P, off)
    end
  end
  in_blueprint_cases()
  bp.inv.destroy()
end

return Q
