-- limits_roster.lua: which builders work when a team's builders go in a
-- batch (region 98).
--   surface: builders = 2, two builders on a surface that is deleted and a
--            third waiting on nauvis: the third takes a place at once
--   release: a team released (mts-v1's on_team_released) with a working and a
--            waiting builder: no error, and a new team on the same force
--            gets the map's limit afresh

local check = require("lib.check")
local rig = require("lib.rig")
local builders = require("lib.builders")

local case = { name = "limits_roster" }

local REGION = 98
local VOID = "seb-lr-void"
local SENSE_SMALL = { ["seb-sense"] = 1, ["seb-sense-entities"] = 1, ["signal-X"] = 0, ["signal-Y"] = 0, ["signal-W"] = 4, ["signal-H"] = 4 }

local function state()
  return storage.limits_roster
end

local function waiting(builder)
  local out = builders.output(builder)
  return out["virtual/seb-error-limit"] == 1 and out["virtual/seb-ack"] == nil, out
end

function case.setup(surface)
  local o = rig.region(REGION)
  rig.floor(surface, rig.box(o, -60, -60, 60, 60))
  local force = rig.own_force("seb-lr")
  rig.call("set_limits", force, { builders = 2 })
  local void = game.create_surface(VOID)
  rig.floor(void, rig.box({ x = 0, y = 0 }, -40, -40, 40, 40))
  local s = { force = force, origin = o }
  s.a, s.a_program = builders.place(void, { x = -10.5, y = 0 }, force)
  s.b, s.b_program = builders.place(void, { x = -10.5, y = 6 }, force)
  s.c, s.c_program = builders.place(surface, rig.offset(o, -10.5, 0), force)
  local team = rig.own_force("seb-lr-team")
  rig.call("set_limits", team, { builders = 1 })
  s.working, s.working_program = builders.place(surface, rig.offset(o, -10.5, 12), team)
  s.waits, s.waits_program = builders.place(surface, rig.offset(o, -10.5, 18), team)
  s.team = team
  storage.limits_roster = s
end

function case.start()
  local s = state()
  for _, program in ipairs({ s.a_program, s.b_program, s.c_program, s.working_program, s.waits_program }) do
    builders.send(program, SENSE_SMALL)
  end
end

case.checks = {
  [120] = function()
    local s = state()
    check.eq("limits_roster the first builders work", builders.output(s.a)["virtual/seb-done"], 1)
    local held, out = waiting(s.c)
    check.truthy("limits_roster a third builder waits", held, check.show(out))
    game.delete_surface(VOID)
    -- A team released: its builders' records go with it.
    local id = remote.call("mts-v1", "get_event_id", "on_team_released")
    script.raise_event(id, { force_name = s.team })
  end,
  [240] = function()
    local s = state()
    local out = builders.output(s.c)
    check.truthy("limits_roster a deleted surface's places go to the oldest waiting builder at once",
      out["virtual/seb-done"] == 1 and out["virtual/seb-error-limit"] == nil, check.show(out))
    -- The released team's builders are nobody's now: a builder placed for
    -- the same force takes the first place again.
    local again, program = builders.place(game.surfaces.nauvis, rig.offset(s.origin, -10.5, 24), s.team)
    builders.send(program, SENSE_SMALL)
    s.again = again
  end,
  [360] = function()
    local s = state()
    local held, out = waiting(s.again)
    check.truthy("limits_roster a released team's force counts its builders afresh",
      not held and out["virtual/seb-done"] == 1, check.show(out))
  end,
}

return case
