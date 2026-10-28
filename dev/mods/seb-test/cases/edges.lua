-- edges.lua: sockets aimed at designs without an entry arrow. Such a child
-- attaches by the middle of its back edge, unturned, so a socket on the first
-- tile outside the parent fits flush.
--   line:    an east socket: copies sit flush in a row
--   down:    a south socket: copies stack flush, all facing north
--   pair:    two entry-less designs that name each other alternate, flush
--   inside:  a socket inside its own design closes as overlaps-parent, marked
--   fill:    east and south sockets fill up to the water and stop there
--   anchor:  a remote stamp at a tile centre is centred there, not off-grid
--   rail:    an entry-less rail design (2x2 grid) whose socket cannot put the
--            child's first row on the socket's tile closes as off-grid

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "edges" }

local D = defines.direction
local LINE_REGION, FILL_REGION = 13, 14
local panel, socket = rig.panel, rig.socket

local LINE = { panel(1.5, 1.5), socket(3.5, 1.5, D.east) }
local DOWN = { panel(1.5, 1.5), socket(1.5, 3.5, D.south) }
local ALPHA = { panel(1.5, 1.5), socket(3.5, 1.5, D.east, "Edge beta") }
local BETA = { { name = "accumulator", position = { x = 1, y = 1 } }, socket(2.5, 0.5, D.east, "Edge alpha") }
local INSIDE = { panel(1.5, 1.5), socket(2.5, 1.5, D.east) }
local FILL = { panel(1.5, 1.5), socket(3.5, 1.5, D.east), socket(1.5, 3.5, D.south) }
local RAIL = { { name = "straight-rail", position = { x = 1, y = 1 } },
  { name = "small-electric-pole", position = { x = 2.5, y = 0.5 } }, socket(3.5, 0.5, D.east) }
-- The fill starts at the origin; water starts at x = 15 and y = 12, so five
-- columns and four rows of 3x3 copies fit.
local COLUMNS, ROWS = 5, 4

local function anchor_case(surface, design, o)
  local id, reason = rig.call("stamp", { force = rig.FORCE, surface = surface, design = design,
    position = rig.offset(o, 40.5, 40.5) })
  check.truthy("edges anchor stamped at a tile centre", id, reason)
  local inst = id and rig.call("get_instance", id)
  check.same("edges anchor centred on the point", inst and inst.footprint, rig.box(o, 39, 39, 42, 42))
end

function case.setup(surface)
  local o = rig.site(surface, LINE_REGION)
  local f = rig.site(surface, FILL_REGION)
  rig.water(surface, rig.box(f, 15, -10, 40, 40))
  rig.water(surface, rig.box(f, -10, 12, 40, 40))
  local e = {
    line = rig.design(LINE, "Edge line"), down = rig.design(DOWN, "Edge down"), alpha = rig.design(ALPHA, "Edge alpha"),
    beta = rig.design(BETA, "Edge beta"), inside = rig.design(INSIDE, "Edge inside"), fill = rig.design(FILL, "Edge fill"),
    rail = rig.design(RAIL, "Edge rail"),
  }
  storage.edges = e
  anchor_case(surface, e.line, o)
end

local function start(design, extra)
  local params = { force = rig.FORCE, surface = game.surfaces.nauvis, design = design, charted_only = false }
  for k, v in pairs(extra) do params[k] = v end
  local id, reason = rig.call("start_project", params)
  check.truthy("edges start design " .. design, id, reason)
  return id
end

function case.start()
  local e, o, f = storage.edges, rig.region(LINE_REGION), rig.region(FILL_REGION)
  e.line_project = start(e.line, { build_position = rig.offset(o, 0, 0), max_instances = 4 })
  e.down_project = start(e.down, { build_position = rig.offset(o, 0, 20), max_instances = 4 })
  e.pair_project = start(e.alpha, { build_position = rig.offset(o, 0, -40), max_instances = 4 })
  e.inside_project = start(e.inside, { build_position = rig.offset(o, 20, -15), max_instances = 3 })
  e.fill_project = start(e.fill, { area = rig.box(f, 0, 0, 100, 100) })
  e.rail_project = start(e.rail, { build_position = rig.offset(o, 12, -20), max_instances = 3 })
end

-- Each copy's footprint begins where the previous one ends along `axis`,
-- and lines up with it on the other axis.
local function flush(label, list, axis)
  for i = 2, #list do
    local a, b = list[i - 1].footprint, list[i].footprint
    local want = axis == "x" and { a.right, a.top } or { a.left, a.bottom }
    check.same(label .. " copy " .. i .. " sits flush", { b.left, b.top }, want)
  end
end

local function check_rows(e)
  local line, down = rig.instances_of(e.line_project), rig.instances_of(e.down_project)
  check.eq("edges line count", #line, 4)
  flush("edges line", line, "x")
  check.eq("edges down count", #down, 4)
  flush("edges down", down, "y")
  local turned = 0
  for _, inst in ipairs(down) do if inst.direction ~= D.north then turned = turned + 1 end end
  check.eq("edges down copies stay unturned", turned, 0)
end

local function check_pair(e)
  local list = rig.instances_of(e.pair_project)
  local designs = {}
  for i, inst in ipairs(list) do designs[i] = inst.design_id end
  check.same("edges pair alternates", designs, { e.alpha, e.beta, e.alpha, e.beta })
  for i = 2, #list do
    check.eq("edges pair copy " .. i .. " starts at the previous edge", list[i].footprint.left, list[i - 1].footprint.right)
  end
end

local function check_inside(e)
  local p = rig.call("get_project", e.inside_project)
  check.eq("edges inside stamps only the seed", p and p.count, 1)
  check.eq("edges inside closes as overlaps-parent", p and p.closed["overlaps-parent"], 1)
  check.eq("edges inside is marked on the map", p and p.blocked, 1)
end

local function check_fill(surface, e)
  local p, f = rig.call("get_project", e.fill_project), rig.region(FILL_REGION)
  check.eq("edges fill finished", p and p.state, "finished")
  check.eq("edges fill count", p and p.count, COLUMNS * ROWS)
  check.eq("edges fill closed at water", p and p.closed.water, COLUMNS + ROWS)
  check.eq("edges fill panels built", rig.count(surface, rig.box(f, 0, 0, 3 * COLUMNS, 3 * ROWS), "solar-panel"), COLUMNS * ROWS)
  check.eq("edges fill nothing on the water", rig.count(surface, rig.box(f, 15, -10, 40, 40), "solar-panel")
    + rig.count(surface, rig.box(f, -10, 12, 15, 40), "solar-panel"), 0)
  local drawn = rig.drawn(surface, rig.box(f, -5, -5, 30, 30))
  check.same("edges fill overlay: a cross per water close, no outlines, no arrows",
    { drawn["seb-overlay-blocked"], drawn.rectangle, drawn["seb-overlay-arrow"] }, { COLUMNS + ROWS })
end

local function check_rail(e)
  local p = rig.call("get_project", e.rail_project) or {}
  check.same("edges rail socket off the 2x2 grid closes as off-grid",
    { p.count, p.closed and p.closed["off-grid"], p.state }, { 1, 1, "finished" })
end

local function verify(surface)
  local e = storage.edges
  check_rail(e)
  check_rows(e)
  check_pair(e)
  check_inside(e)
  check_fill(surface, e)
end

case.checks = { [4200] = verify }

return case
