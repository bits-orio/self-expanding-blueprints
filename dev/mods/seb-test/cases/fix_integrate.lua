-- fix_integrate.lua: where this round's workstreams meet (region 172).
--   capture: a builder's Capture of an area that draws more sockets than a
--            design may (const.MAX_DESIGN_SOCKETS) answers ERR with the limit
--            error: prepare.lua refuses it as too-many-sockets when it is
--            registered, and answer.lua names that error; at the cap it is
--            captured
--   poles:   a carpet of more electric poles than a design may have
--            (const.MAX_DESIGN_POLES) is refused as too-many-poles; one at
--            the cap registers and stamps, and how long each took is an
--            INFO line

local check = require("lib.check")
local rig = require("lib.rig")
local builders = require("lib.builders")

local case = { name = "fix_integrate" }

local REGION = 172
local CAP = 64             -- const.MAX_DESIGN_SOCKETS
local W, H = 12, 8         -- the captured rectangle, from a site's corner
local POLES = 1000         -- const.MAX_DESIGN_POLES

-- A chest and `n` sockets, ten to a row, from `at` (a tile corner), and a
-- builder west of them; returns its builder and program.
local function capture_site(surface, at, n)
  local force = rig.FREE_FORCE
  surface.create_entity { name = "iron-chest", position = { at.x + 0.5, at.y + 0.5 }, force = force }
  for i = 0, n - 1 do
    surface.create_entity { name = "seb-socket", force = force, direction = defines.direction.east,
      position = { at.x + 1.5 + i % 10, at.y + 0.5 + math.floor(i / 10) } }
  end
  local builder, program = builders.place(surface, rig.offset(at, -6.5, 2), force)
  return { at = at, builder = builder, program = program }
end

-- `n` small electric poles, one a tile, forty to a row.
local function carpet(n)
  local list = {}
  for i = 0, n - 1 do
    list[#list + 1] = { name = "small-electric-pole", position = { x = i % 40 + 0.5, y = math.floor(i / 40) + 0.5 } }
  end
  return rig.blueprint(list, { label = "Pole carpet" })
end

local function timed(what, fn)
  local profiler = helpers.create_profiler()
  local a, b = fn()
  profiler.stop()
  log({ "", "SEB_TEST INFO fix_integrate a carpet of ", POLES, " poles ", what, " in ", profiler })
  return a, b
end

local function poles_case(surface, o)
  local force = rig.FREE_FORCE
  rig.floor(surface, rig.box(o, -60, -110, 110, -12))
  local over, why = rig.call("register_design", force, carpet(POLES + 1))
  check.same("fix_integrate more poles than a design may have are refused", { over, why }, { nil, "too-many-poles" })
  local id = timed("registered", function() return rig.call("register_design", force, carpet(POLES)) end)
  check.truthy("fix_integrate as many poles as a design may have register", id, check.show(id))
  local instance, reason = timed("stamped", function()
    return rig.call("stamp", { force = force, surface = surface.name, design = id, position = rig.offset(rig.region(REGION), 8, -60) })
  end)
  check.truthy("fix_integrate a carpet of as many poles as a design may have stamps", instance, check.show(reason))
end

function case.setup(surface)
  local o = rig.region(REGION)
  rig.own_force(rig.FREE_FORCE)
  rig.floor(surface, rig.box(o, -20, -10, 50, 20))
  storage.fix_integrate = {
    over = capture_site(surface, o, CAP + 1),
    at_cap = capture_site(surface, rig.offset(o, 25, 0), CAP),
  }
  poles_case(surface, o)
end

local function capture(site)
  builders.send(site.program, { ["seb-capture"] = 1, ["signal-X"] = site.at.x, ["signal-Y"] = site.at.y,
    ["signal-W"] = W, ["signal-H"] = H, ["seb-absolute"] = 1 })
end

function case.start()
  local s = storage.fix_integrate
  capture(s.over)
  capture(s.at_cap)
end

local function captured()
  local s = storage.fix_integrate
  local over, at_cap = builders.output(s.over.builder), builders.output(s.at_cap.builder)
  check.truthy("fix_integrate a Capture drawing more sockets than a design may answers the limit error",
    builders.failed(over, 1, "limit"), check.show(over))
  check.truthy("fix_integrate a Capture drawing as many sockets as a design may is captured",
    at_cap["virtual/seb-done"] == 1 and at_cap["virtual/seb-design"] ~= nil, check.show(at_cap))
end

case.checks = { [240] = captured }

return case
