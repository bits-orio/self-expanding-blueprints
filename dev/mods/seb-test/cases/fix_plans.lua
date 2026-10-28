-- fix_plans.lua: plans and the growth loop under load (regions 120-129,
-- DESIGN.md "Sharing a server"). The capacity scenario has a force of its
-- own; the plan, which needs no limits, the shared rig.FREE_FORCE.
--   limit:    a plan of a design with 64 drawn sockets reaches the plan
--             limit, and every socket still open closes at once, counted as
--             count-reached with one history line: the plan is done right
--             after its last copy
--   overlay:  while that plan grows, its open sockets far outnumber the
--             arrows it shows (at most MAX_DRAWN_SOCKETS), and each planned
--             copy has one outline, drawn once
--   capacity: a project held at the capacity gate by its force's cap grows
--             on once a copy settles after the cap was set to 0 (no limit)

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "fix_plans" }

local PLAN, CAP = 120, 121
local LIMIT = 400          -- plan.LIMIT: a plan stops at this many copies
local MAX_DRAWN = 100      -- const.MAX_DRAWN_SOCKETS
local SOCKETS = 64
local REACH = 199          -- tiles around a region's origin that only its scenario uses
local FIRST_POLL, LAST_POLL = 120, 6000

local function name(key) return "fix_plans " .. key end

local function project(id) return id and rig.call("get_project", id) or {} end

-- One chest and `k` drawn sockets around it, all pointing east with no
-- design named (each grows the design again).
local function socket_design(k)
  local list = { { name = "iron-chest", position = { x = 0.5, y = 0.5 } } }
  local half = math.floor(math.ceil(math.sqrt(k + 1)) / 2)
  for dx = -half, half do
    for dy = -half, half do
      if #list <= k and not (dx == 0 and dy == 0) then
        list[#list + 1] = rig.socket(dx + 0.5, dy + 0.5, defines.direction.east)
      end
    end
  end
  return list
end

local function plan_box()
  return rig.box(rig.region(PLAN), -REACH, -REACH, REACH, REACH)
end

function case.setup(surface)
  local s = { polls = {} }
  storage.fix_plans = s
  s.plan_force = rig.own_force(rig.FREE_FORCE)
  rig.floor(surface, rig.box(rig.region(PLAN), -100, -100, 100, 100))
  s.design = rig.call("register_design", s.plan_force, rig.blueprint(socket_design(SOCKETS), { label = "Many sockets" }))
  s.cap_force = rig.own_force("seb-fp-cap")
  rig.call("set_limits", s.cap_force, { building = 1 })
  local c = rig.region(CAP)
  rig.floor(surface, rig.box(c, -60, -60, 60, 60))
  -- Robots, but no panel to build with yet: a copy stays under construction.
  s.chest = rig.network(surface, rig.offset(c, -25, -25), {}, s.cap_force)
  s.cell = rig.call("register_design", s.cap_force, rig.blueprint({ rig.panel(1.5, 1.5) }, { label = "Cap cell" }))
end

function case.start(surface)
  local s = storage.fix_plans
  s.plan = rig.call("start_project", {
    force = s.plan_force, surface = surface, design = s.design, position = rig.region(PLAN), dry_run = true,
    charted_only = false,
  })
  local function cap_project(dx)
    return rig.call("start_project", { force = s.cap_force, surface = surface, design = s.cell, charted_only = false,
      build_position = rig.offset(rig.region(CAP), dx, 0), materials = false, max_instances = 1 })
  end
  s.cap_a, s.cap_b = cap_project(0), cap_project(10)
  check.truthy(name("projects start"), s.plan and s.cap_a and s.cap_b)
end

function case.on_event(event_name, payload)
  local s = storage.fix_plans
  if s and event_name == "on_project_finished" and payload.project_id == s.plan then s.finished_tick = game.tick end
end

local function an_outline(surface)
  local box = plan_box()
  for _, object in pairs(rendering.get_all_objects(rig.REMOTE)) do
    local p = object.type == "rectangle" and object.surface.index == surface.index and object.left_top.position
    if p and p.x >= box.left and p.x < box.right and p.y >= box.top and p.y < box.bottom then return object end
  end
end

-- What the plan holds and draws, once a second while it grows.
local function poll(surface)
  local s = storage.fix_plans
  local p = project(s.plan)
  local drawn = rig.drawn(surface, plan_box())
  s.polls[#s.polls + 1] = {
    tick = game.tick, count = p.count or 0, open = (p.open_sockets or 0) + (p.parked or 0),
    arrows = drawn["seb-overlay-arrow"] or 0, outlines = drawn.rectangle or 0,
  }
  s.outline = s.outline or an_outline(surface)
end

local function history_lines(p, reason)
  local n = 0
  for _, entry in ipairs(p.history or {}) do
    if entry.reason == reason then n = n + 1 end
  end
  return n
end

local function limit_check()
  local s = storage.fix_plans
  local p = project(s.plan)
  check.same(name("limit the plan stops at its limit with nothing left open"),
    { p.count, p.open_sockets, p.parked, p.status and p.status.level }, { LIMIT, 0, 0, "planned" })
  local reached
  for _, entry in ipairs(s.polls) do
    if not reached and entry.count >= LIMIT then reached = entry end
  end
  check.info(name("limit first seen at the limit " .. check.show(reached) .. ", finished at " .. tostring(s.finished_tick)))
  check.truthy(name("limit the rest closed right after the last copy"),
    reached and s.finished_tick and s.finished_tick <= reached.tick + 60,
    check.show({ reached = reached, finished = s.finished_tick }))
  check.truthy(name("limit every open socket closed as count-reached"),
    (p.closed and p.closed["count-reached"] or 0) > MAX_DRAWN, check.show(p.closed))
  check.eq(name("limit the history says so once"), history_lines(p, "count-reached"), 1)
end

local function overlay_check(surface)
  local s = storage.fix_plans
  local most_open, most_arrows = 0, 0
  for _, entry in ipairs(s.polls) do
    most_open, most_arrows = math.max(most_open, entry.open), math.max(most_arrows, entry.arrows)
  end
  check.info(name("overlay at most " .. most_open .. " sockets open, " .. most_arrows .. " arrows drawn"))
  check.truthy(name("overlay the plan had more open sockets than it may draw"), most_open > MAX_DRAWN, most_open)
  check.truthy(name("overlay draws at most MAX_DRAWN_SOCKETS arrows"), most_arrows <= MAX_DRAWN, most_arrows)
  check.eq(name("overlay one outline per planned copy"), rig.drawn(surface, plan_box()).rectangle, LIMIT)
  check.truthy(name("overlay an outline is drawn once"), s.outline and s.outline.valid)
end

local function capacity_hold()
  local s = storage.fix_plans
  local a, b = project(s.cap_a), project(s.cap_b)
  check.same(name("capacity A's copy waits for a panel, B is held by the force's cap"),
    { a.count, a.building, b.count, b.gate }, { 1, 1, 0, "capacity" })
  rig.call("set_limits", s.cap_force, { building = 0 })
  s.chest.insert { name = "solar-panel", count = 2 }
end

local function capacity_after()
  local s = storage.fix_plans
  check.eq(name("capacity B grows on once A's copy settles, with no cap left"), project(s.cap_b).count, 1)
end

case.checks = {
  [300] = capacity_hold, [1500] = capacity_after,
  [LAST_POLL + 60] = function(surface)
    limit_check()
    overlay_check(surface)
  end,
}
for tick = FIRST_POLL, LAST_POLL, 60 do
  local other = case.checks[tick]
  case.checks[tick] = function(surface)
    poll(surface)
    if other then other(surface) end
  end
end

return case
