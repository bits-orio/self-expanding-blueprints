-- fix_server.lua: the whole server's time, taken by the teams in turns
-- (regions 140-141; DESIGN.md D44, scripts/core/server_budget.lua). Two
-- teams, each with its own share, plan the same 100-part design over three
-- areas each; a planned copy is charged by the parts it checked (200 µs).
-- At tick 240 team A registers a big design: one piece of some 40 ms,
-- charged to A alone.
--   Always: both teams progress, alike (the same load), B's progress right
--   after A's big piece is not held up, and A goes on after it.
--   With seb-work-per-tick set below the load, the two together also stay
--   near that rate over ticks 120 to 240, counted in planned copies. The
--   suite runs with it off (settings-final-fixes.lua), and no test mod can
--   change another mod's setting: to run this check, set its default to
--   200 there in a scratch copy and run this case alone.

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "fix_server" }

local REGIONS = { a = 140, b = 141 }
local SIDE, AREA, AREAS = 10, 150, { { 0, 0 }, { 160, 0 }, { 0, 160 } }
local COPY_COST = SIDE * SIDE * 2   -- budget.COST.check_part per part checked
local SHARE = 400                   -- each team's own µs per tick, above what its plans ask
local LOAD = 600                    -- µs per tick both teams' plans ask together (measured with no server rate)
local BIG = 30                      -- the big design: BIG x BIG lamps

local function name(key) return "fix_server " .. key end

local function grid(side, entity)
  local list = {}
  for x = 0, side - 1 do
    for y = 0, side - 1 do list[#list + 1] = { name = entity, position = { x = x + 0.5, y = y + 0.5 } } end
  end
  return list
end

local function team(key, surface)
  local force = rig.own_force("seb-fs-" .. key)
  rig.call("set_limits", force, { work = SHARE })
  local o = rig.region(REGIONS[key])
  rig.floor(surface, rig.box(o, -5, -5, 320, 320))
  local text = rig.blueprint(grid(SIDE, "wooden-chest"), { label = "Server " .. key })
  return { force = force, origin = o, design = rig.call("register_design", force, text), plans = {} }
end

function case.setup(surface)
  storage.fix_server = { a = team("a", surface), b = team("b", surface), counts = {} }
end

function case.start(surface)
  for _, t in pairs({ storage.fix_server.a, storage.fix_server.b }) do
    for i, at in ipairs(AREAS) do
      t.plans[i] = rig.call("start_project", {
        force = t.force, surface = surface, design = t.design, dry_run = true, charted_only = false,
        area = rig.box(t.origin, at[1], at[2], at[1] + AREA, at[2] + AREA),
      })
    end
  end
end

-- Planned copies of a team's plans so far.
local function copies(t)
  local n = 0
  for _, id in ipairs(t.plans) do n = n + ((rig.call("get_project", id) or {}).count or 0) end
  return n
end

local function sample(tick)
  local s = storage.fix_server
  s.counts[tick] = { a = copies(s.a), b = copies(s.b) }
end

local function gained(key, from, to)
  local counts = storage.fix_server.counts
  return counts[to][key] - counts[from][key]
end

-- Both progress, alike; with a server rate, together near it.
local function check_turns()
  local a, b = gained("a", 120, 240), gained("b", 120, 240)
  check.truthy(name("both teams progress"), a > 0 and b > 0, "a " .. a .. ", b " .. b)
  check.truthy(name("the same load, alike"), math.abs(a - b) <= 0.2 * (a + b), "a " .. a .. ", b " .. b)
  local rate = settings.global["seb-work-per-tick"].value
  if rate == 0 or rate > LOAD / 2 then
    return check.info(name("seb-work-per-tick is off or above the load: the rate is not checked"))
  end
  local want = rate * 120 / COPY_COST
  check.truthy(name("together near the server's rate"), a + b >= 0.7 * want and a + b <= 1.3 * want,
    ("%d copies in 120 ticks, %d at the rate"):format(a + b, want))
end

-- One big piece of A's: registering a design of BIG x BIG lamps.
local function big_piece()
  local s = storage.fix_server
  s.big = rig.call("register_design", s.a.force, rig.blueprint(grid(BIG, "small-lamp"), { label = "Server big" }))
  check.truthy(name("the big design registers"), s.big)
end

case.checks = {
  [120] = function() sample(120) end,
  [180] = function() sample(180) end,
  [240] = function()
    sample(240)
    check_turns()
    big_piece()
  end,
  [300] = function()
    sample(300)
    local before, after = gained("b", 180, 240), gained("b", 240, 300)
    check.truthy(name("B is not held up by A's big piece"), after >= 0.8 * before,
      "before " .. before .. ", after " .. after)
  end,
  [600] = function()
    sample(600)
    local counts = storage.fix_server.counts
    check.info(name("planned copies by tick ") .. check.show(counts))
    check.truthy(name("A goes on after its big piece"), gained("a", 300, 600) > 0, check.show(counts))
  end,
}

return case
