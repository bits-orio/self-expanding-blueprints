-- sockets.lua: drawn sockets and their alignment.
--   line:      entry on the west edge, socket just east: copies sit flush in a line
--   turn:      a south socket on that design turns the child so its entry faces south
--   alternate: a socket naming another design stamps that design
--   grid:      implicit growth steps by the blueprint's snap grid, not its footprint

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "sockets" }

local D = defines.direction
local LINE_REGION, NAMED_REGION, GRID_REGION = 5, 6, 7

local panel, socket, entry = rig.panel, rig.socket, rig.entry

local LINE = { panel(1.5, 1.5), entry(0.5, 1.5, D.east), socket(3.5, 1.5, D.east) }
local TURN = { panel(1.5, 1.5), entry(0.5, 1.5, D.east), socket(1.5, 3.5, D.south) }
local ALPHA = { panel(1.5, 1.5), entry(0.5, 1.5, D.east), socket(3.5, 1.5, D.east, "Beta cell") }
local BETA = {
  { name = "accumulator", position = { x = 1, y = 1 } },
  entry(0.5, 0.5, D.east), socket(2.5, 0.5, D.east, "Alpha cell"),
}
local GRIDDED = { panel(1.5, 1.5) }
-- Socket two tiles beyond the east edge and one tile down: each copy steps
-- east by its width plus 2 and shifts south by 1.
local OFFSET = { panel(1.5, 1.5), entry(0.5, 1.5, D.east), socket(5.5, 2.5, D.east) }

function case.setup(surface)
  rig.site(surface, LINE_REGION)
  rig.site(surface, NAMED_REGION)
  rig.site(surface, GRID_REGION)
  local s = {}
  s.line = rig.design(LINE, "Line cell")
  s.turn = rig.design(TURN, "Turn cell")
  s.alpha = rig.design(ALPHA, "Alpha cell")
  s.beta = rig.design(BETA, "Beta cell")
  s.grid = rig.design(GRIDDED, "Grid cell", { grid = { x = 5, y = 5 } })
  s.offset = rig.design(OFFSET, "Offset cell")
  storage.sockets = s
end

local function start(design, region, dx, dy, extra)
  local params = {
    force = rig.FORCE, surface = game.surfaces.nauvis, design = design,
    build_position = rig.offset(rig.region(region), dx, dy), charted_only = false,
  }
  for k, v in pairs(extra or {}) do params[k] = v end
  local project, reason = rig.call("start_project", params)
  check.truthy("sockets start design " .. design, project, reason)
  return project
end

function case.start(surface)
  local s = storage.sockets
  s.line_project = start(s.line, LINE_REGION, 0, 0, { max_instances = 4 })
  s.turn_project = start(s.turn, LINE_REGION, 0, 20, { max_instances = 3 })
  s.alpha_project = start(s.alpha, NAMED_REGION, 0, 0, { max_instances = 4 })
  s.grid_project = start(s.grid, GRID_REGION, 0, 0, { max_instances = 3, directions = { D.east } })
  s.offset_project = start(s.offset, GRID_REGION, 0, 20, { max_instances = 3 })
end

local function lefts(list)
  local out = {}
  for i, inst in ipairs(list) do out[i] = { inst.footprint.left, inst.footprint.top } end
  return out
end

local function check_line(s)
  local list = rig.instances_of(s.line_project)
  check.eq("sockets line count", #list, 4)
  local o = rig.region(LINE_REGION)
  local first = list[1] and list[1].footprint
  if not first then return end
  local want = {}
  for i = 0, 3 do want[i + 1] = { first.left + 3 * i, first.top } end
  check.same("sockets line copies sit flush", lefts(list), want)
  check.truthy("sockets line all complete", #list == 4 and list[4].state == "complete", check.show(list[4] and list[4].state))
end

local function check_turn(s)
  local list = rig.instances_of(s.turn_project)
  check.eq("sockets turn count", #list, 3)
  if #list < 2 then return end
  local a, b = list[1], list[2]
  check.eq("sockets turn child is turned", b.direction, D.east)
  check.same("sockets turn child sits flush south", { b.footprint.left, b.footprint.top },
    { a.footprint.left, a.footprint.bottom })
end

local function check_named(s)
  local list = rig.instances_of(s.alpha_project)
  check.eq("sockets alternate count", #list, 4)
  local names = {}
  for i, inst in ipairs(list) do names[i] = inst.design_id end
  check.same("sockets alternate designs", names, { s.alpha, s.beta, s.alpha, s.beta })
end

local function check_grid(s)
  local list = rig.instances_of(s.grid_project)
  check.eq("sockets grid count", #list, 3)
  if #list < 3 then return end
  check.eq("sockets grid step", list[2].position.x - list[1].position.x, 5)
  check.eq("sockets grid step again", list[3].position.x - list[2].position.x, 5)
end

local function check_offset(s)
  local list = rig.instances_of(s.offset_project)
  check.eq("sockets offset count", #list, 3)
  if #list < 3 then return end
  for i = 2, 3 do
    local dx = list[i].footprint.left - list[i - 1].footprint.left
    local dy = list[i].footprint.top - list[i - 1].footprint.top
    check.same("sockets offset step " .. i, { dx, dy }, { 5, 1 })
  end
end

local function verify()
  local s = storage.sockets
  check_line(s)
  check_turn(s)
  check_named(s)
  check_grid(s)
  check_offset(s)
end

case.checks = { [3000] = verify }

return case
