-- fix_builders.lua: the second griefing round's builder fixes (regions
-- 130-139, DESIGN.md D44 and D45). Every scenario but grow, which needs no
-- limits (rig.FREE_FORCE), has a force of its own.
--   cap:  a project held at the capacity gate grows on when its team's cap is
--         raised (set_limits building = 2), lifted (building = 0) or dropped
--         (clear_limits); a team whose cap stays holds it
--   rate: a plan waiting for its team's share of server time and a builder
--         told to wait for it look again at once when the rate changes
--         (set_limits work = 0), not when the old rate would have let them
--   grow: a running Grow shows the ghosts of the copies being built; once it
--         ends the builder goes on showing what it showed then
--   lost: a builder whose output combinator was lost, merged into a team
--         that has no place for it: it waits showing the limit error, and
--         its output is made again
-- (3,000 unwired builders are fix_builders_many.lua, region 136.)

local check = require("lib.check")
local rig = require("lib.rig")
local builders = require("lib.builders")

local case = { name = "fix_builders" }

local CAPS = {
  { key = "raise", region = 130, change = function(force) rig.call("set_limits", force, { building = 2 }) end },
  { key = "lift", region = 131, change = function(force) rig.call("set_limits", force, { building = 0 }) end },
  { key = "clear", region = 132, change = function(force) rig.call("clear_limits", force) end },
  { key = "hold", region = 133 },
}
local RATE, GROW, LOST = 134, 135, 137
local CELL = { rig.panel(1.5, 1.5) }
local TRIPLE = { rig.panel(1.5, 1.5), rig.panel(4.5, 1.5), rig.panel(7.5, 1.5) }
local AT = { -10.5, 0 }

local function fb()
  return storage.fix_builders
end

-- A force of its own with these limits, and a floor around its region.
local function team(surface, region, name, limits)
  local o = rig.region(region)
  rig.floor(surface, rig.box(o, -60, -60, 60, 60))
  local force = rig.own_force(name)
  if limits then rig.call("set_limits", force, limits) end
  return force, o
end

local function register(force, entities, label)
  return rig.call("register_design", force, rig.blueprint(entities, { label = label }))
end

-- No network: a copy stays under construction, and fills the cap of one.
local function cap_setup(surface)
  local list = {}
  for i, c in ipairs(CAPS) do
    local force, o = team(surface, c.region, "seb-fb-cap-" .. c.key, { building = 1 })
    list[i] = { force = force, origin = o, design = register(force, CELL, "fix_builders " .. c.key) }
  end
  return list
end

local function cap_start(surface)
  for _, t in ipairs(fb().cap) do
    local function project(dx)
      return rig.call("start_project", { force = t.force, surface = surface, design = t.design, charted_only = false,
        build_position = rig.offset(t.origin, dx, 0), materials = false, max_instances = 1 })
    end
    t.a, t.b = project(0), project(10)
  end
end

local function cap_held()
  for i, c in ipairs(CAPS) do
    local t = fb().cap[i]
    local a, b = rig.call("get_project", t.a), rig.call("get_project", t.b)
    check.same("fix_builders cap " .. c.key .. ": one copy fills the team's cap, the other project is held",
      { a.count, a.building, b.count, b.gate }, { 1, 1, 0, "capacity" })
    if c.change then c.change(t.force) end
  end
end

local function cap_grown()
  for i, c in ipairs(CAPS) do
    local b = rig.call("get_project", fb().cap[i].b)
    if c.change then
      check.eq("fix_builders cap " .. c.key .. ": the held project grows on at once", b.count, 1)
    else
      check.same("fix_builders cap " .. c.key .. ": a cap that stays keeps it held", { b.count, b.gate }, { 0, "capacity" })
    end
  end
end

-- A share of 1 microsecond a tick, and a Sense over four whole chunks: its
-- first chunk leaves the team in debt for about a thousand ticks.
local function rate_setup(surface)
  local force, o = team(surface, RATE, "seb-fb-rate")
  -- Registered before the team has a share: only the request is charged.
  local design = register(force, CELL, "fix_builders rate")
  local builder, program = builders.place(surface, rig.offset(o, AT[1], AT[2]), force)
  rig.call("set_limits", force, { work = 1 })
  local left, top = math.floor(o.x / 32) * 32 - 32, math.floor(o.y / 32) * 32 - 32
  return { force = force, origin = o, design = design, builder = builder, program = program,
    request = { ["seb-sense"] = 1, ["seb-sense-entities"] = 1, ["seb-absolute"] = 1, ["signal-X"] = left, ["signal-Y"] = top,
      ["signal-W"] = 64, ["signal-H"] = 64 } }
end

local function waited_busy(history)
  for _, entry in ipairs(history or {}) do
    if entry.kind == "waiting" and entry.reason == "busy" then return true end
  end
  return false
end

local function rate_waiting(surface)
  local r = fb().rate
  local out = builders.output(r.builder)
  check.truthy("fix_builders rate: the builder waits for its team's share", out["virtual/seb-ack"] == 1
    and out["virtual/seb-done"] == nil, check.show(out))
  r.plan = rig.call("start_project", { force = r.force, surface = surface, design = r.design, charted_only = false,
    position = rig.offset(r.origin, 10, 10), dry_run = true })
end

local function rate_changed()
  local r = fb().rate
  local plan = rig.call("get_project", r.plan)
  check.truthy("fix_builders rate: the plan waits its turn", plan.count == 0 and waited_busy(plan.history), check.show(plan))
  check.eq("fix_builders rate: the builder still waits", builders.output(r.builder)["virtual/seb-done"], nil)
  rig.call("set_limits", r.force, { work = 0 })
end

local function rate_served()
  local r = fb().rate
  check.eq("fix_builders rate: the builder is read again at once", builders.output(r.builder)["virtual/seb-done"], 1)
  check.truthy("fix_builders rate: the plan has its turn at once", rig.call("get_project", r.plan).count > 0)
end

-- No network at first: the first copy goes down and stays under construction.
local function grow_setup(surface)
  local force, o = team(surface, GROW, rig.FREE_FORCE)
  local builder, program = builders.place(surface, rig.offset(o, AT[1], AT[2]), force)
  return { force = force, origin = o, design = register(force, TRIPLE, "fix_builders triple"), builder = builder, program = program }
end

local function grow_start()
  local g = fb().grow
  builders.send(g.program, { ["seb-grow"] = 1, ["seb-design"] = g.design, ["signal-X"] = -22, ["signal-Y"] = -12,
    ["seb-count"] = 2, ["seb-grow-east"] = 1 })
end

local function grow_running()
  local g = fb().grow
  local out = builders.output(g.builder)
  check.truthy("fix_builders grow: a running Grow shows the ghosts of its copy", out["virtual/seb-ghosts-left"] == 3
    and out["virtual/seb-ack"] == 1 and out["virtual/seb-done"] == nil, check.show(out))
  check.eq("fix_builders grow: ... and the bill of the next copy", out["item/solar-panel"], 3)
  builders.send(g.program, { ["seb-stop"] = 1 })
end

local function grow_stopped(surface)
  local g = fb().grow
  local out = builders.output(g.builder)
  check.truthy("fix_builders grow: Stop ends it", out["virtual/seb-done"] == 1 and out["virtual/seb-ghosts-left"] == 3, check.show(out))
  check.eq("fix_builders grow: a stopped Grow asks for no more materials", out["item/solar-panel"], nil)
  rig.network(surface, rig.offset(g.origin, -25, -25), nil, g.force)
end

local function grow_ended(surface)
  local g = fb().grow
  check.eq("fix_builders grow: the robots built the copy", rig.count(surface, rig.box(g.origin, -40, -20, -20, 0), "solar-panel"), 3)
  check.eq("fix_builders grow: the builder goes on showing what it showed when it ended",
    builders.output(g.builder)["virtual/seb-ghosts-left"], 3)
end

-- Two teams, each with a wired builder; the first team's has lost its output.
local function lost_setup(surface)
  local into, o = team(surface, LOST, "seb-fb-lost-into", { builders = 1 })
  local from = rig.own_force("seb-fb-lost-from")
  local kept, kept_program = builders.place(surface, rig.offset(o, AT[1], AT[2] + 12), into)
  local moved, moved_program = builders.place(surface, rig.offset(o, AT[1], AT[2]), from)
  return { into = into, from = from, kept = kept, moved = moved, programs = { kept_program, moved_program } }
end

local function lost_output(surface, builder)
  return surface.find_entities_filtered { name = "seb-builder-output", position = builder.position, radius = 0.5 }
end

local function lost_merge(surface)
  local l = fb().lost
  for _, output in ipairs(lost_output(surface, l.moved)) do output.destroy() end
  check.eq("fix_builders lost: the output is gone", #lost_output(surface, l.moved), 0)
  game.merge_forces(l.from, l.into)
end

local function lost_waits(surface)
  local l = fb().lost
  local out = builders.output(l.moved)
  check.truthy("fix_builders lost: the merged builder waits for a place, showing the limit error",
    out["virtual/seb-error-limit"] == 1, check.show(out))
  check.eq("fix_builders lost: its output was made again", #lost_output(surface, l.moved), 1)
  check.eq("fix_builders lost: the other team's builder still works", builders.output(l.kept)["virtual/seb-error-limit"], nil)
end

function case.setup(surface)
  storage.fix_builders = {
    cap = cap_setup(surface), rate = rate_setup(surface), grow = grow_setup(surface), lost = lost_setup(surface),
  }
end

function case.start(surface)
  cap_start(surface)
  builders.send(fb().rate.program, fb().rate.request)
  grow_start()
end

case.checks = {
  [120] = function(surface) rate_waiting(surface) grow_running() end,
  [180] = function() cap_held() rate_changed() end,
  [240] = function(surface) grow_stopped(surface) end,
  [300] = function() cap_grown() rate_served() end,
  [360] = lost_merge,
  [420] = lost_waits,
  [900] = grow_ended,
}

return case
