-- Q8 cost (S5-lite): build_blueprint of a ~125-entity design, the per-entity
-- pre-check, a ghost recount, and calibration in four directions.
local fmt = require("lib.fmt")
local B = require("lib.bp")
local D = require("lib.designs")
local events = require("lib.events")
local Q = {id = "Q8"}

local N = 200
local DIRS = {0, 4, 8, 12}

local function solar_spec()
  local list = {}
  for i = 0, 9 do
    for j = 0, 9 do list[#list + 1] = D.ent("solar-panel", 1.5 + 4 * i, 1.5 + 4 * j) end
  end
  for i = 0, 4 do
    for j = 0, 4 do list[#list + 1] = D.ent("medium-electric-pole", 3.5 + 8 * i, 3.5 + 8 * j) end
  end
  return {id = "solar", entities = list}
end

local function report(label, prof, n)
  log({"", "SEB_SPIKE Q8 ", label, " total(", n, ") ", prof})
  prof.divide(n)
  log({"", "SEB_SPIKE Q8 ", label, " per_call ", prof})
end

local function destroy_all(list)
  for _, g in pairs(list) do if g.valid then g.destroy() end end
end

local function build_loop(bp, s, P, raise_built)
  local p_build, p_destroy = helpers.create_profiler(true), helpers.create_profiler(true)
  local counts = {}
  for _ = 1, N do
    p_build.restart()
    local ret = bp.stack.build_blueprint({surface = s, force = "player", position = P, direction = 0,
      build_mode = defines.build_mode.forced, raise_built = raise_built})
    p_build.stop()
    counts[#ret] = (counts[#ret] or 0) + 1
    p_destroy.restart()
    destroy_all(ret)
    p_destroy.stop()
  end
  return p_build, p_destroy, counts
end

local function precheck_loop(bp, s, P)
  -- the offsets of each entity at d = 0, from one stamp
  local ret = bp.stack.build_blueprint({surface = s, force = "player", position = P, direction = 0,
    build_mode = defines.build_mode.forced})
  local plan = {}
  for _, g in pairs(ret) do plan[#plan + 1] = {name = g.ghost_name, position = g.position, direction = g.direction} end
  destroy_all(ret)
  local prof = helpers.create_profiler()
  local ok_all = 0
  for _ = 1, N do
    local ok = true
    for _, e in ipairs(plan) do
      if not s.can_place_entity({name = e.name, position = e.position, direction = e.direction, force = "player",
        build_check_type = defines.build_check_type.blueprint_ghost, forced = true}) then ok = false end
    end
    if ok then ok_all = ok_all + 1 end
  end
  prof.stop()
  return prof, #plan, ok_all
end

local function recount_loop(bp, s, P)
  local ret = bp.stack.build_blueprint({surface = s, force = "player", position = P, direction = 0,
    build_mode = defines.build_mode.forced})
  local area = {{P.x - 25, P.y - 25}, {P.x + 25, P.y + 25}}
  local prof = helpers.create_profiler()
  local n = 0
  for _ = 1, N do n = s.count_entities_filtered({area = area, type = "entity-ghost"}) end
  prof.stop()
  destroy_all(ret)
  return prof, n
end

local function calibration_loop(bp, s, reps)
  local prof = helpers.create_profiler()
  local seen = 0
  for _ = 1, reps do
    for _, d in ipairs(DIRS) do
      local ret = bp.stack.build_blueprint({surface = s, force = "player", position = {x = 0, y = 0}, direction = d,
        build_mode = defines.build_mode.forced, raise_built = false})
      for _, g in pairs(ret) do
        local _ = g.position
        seen = seen + 1
      end
      destroy_all(ret)
    end
  end
  prof.stop()
  return prof, seen
end

-- In a running game, with a script_raised_built handler that only counts.
function Q.tick()
  local s = game.surfaces.nauvis
  local bp = B.new(solar_spec())
  events.start()
  local pb, pd = build_loop(bp, s, {x = -600, y = 0}, true)
  local w = events.stop()
  fmt.out("Q8.tick=" .. game.tick .. " script_raised_built events over " .. N .. " builds=" .. tostring(w.script_raised_built))
  report("tick-phase build_blueprint raise_built=true with counting handler", pb, N)
  report("tick-phase destroy returned ghosts", pd, N)
  local pb2 = build_loop(bp, s, {x = -600, y = 0}, false)
  report("tick-phase build_blueprint raise_built=false", pb2, N)
  bp.inv.destroy()
end

function Q.run()
  local s = game.surfaces.nauvis
  local P = {x = -600, y = 0}
  local bp = B.new(solar_spec())
  local n = #bp.ent_list
  fmt.out("Q8.design solar entities=" .. n)
  local pb, pd, counts = build_loop(bp, s, P, true)
  fmt.out("Q8 ghosts_per_build histogram " .. fmt.line(counts))
  report("build_blueprint raise_built=true (" .. n .. " entities, forced, nauvis)", pb, N)
  report("destroy returned ghosts", pd, N)
  local pb2, _, _ = build_loop(bp, s, P, false)
  report("build_blueprint raise_built=false", pb2, N)
  local pc, nplan, okc = precheck_loop(bp, s, P)
  fmt.out("Q8 precheck entities=" .. nplan .. " passes=" .. okc .. "/" .. N)
  report("can_place_entity pre-check of all entities", pc, N)
  local pr, ghosts = recount_loop(bp, s, P)
  fmt.out("Q8 recount ghosts=" .. ghosts)
  report("count_entities_filtered recount over footprint", pr, N)
  local cal = game.get_surface("seb-spike-calibration")
  local bpa = B.new(D.a)
  local pcal, seen = calibration_loop(bpa, cal, 50)
  bpa.inv.destroy()
  fmt.out("Q8 calibration design a: ghosts read=" .. seen .. " over 50x4 stamps")
  report("calibration of design a in 4 directions", pcal, 50)
  local pcal2, seen2 = calibration_loop(bp, cal, 10)
  fmt.out("Q8 calibration solar: ghosts read=" .. seen2 .. " over 10x4 stamps")
  report("calibration of solar design in 4 directions", pcal2, 10)
  local pb3 = build_loop(bp, cal, {x = 0, y = 0}, true)
  report("build_blueprint raise_built=true on calibration surface", pb3, N)
  bp.inv.destroy()
end

return Q
