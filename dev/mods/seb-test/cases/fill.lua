-- fill.lua: the v0.1 acceptance test (DESIGN.md section 8).
-- A solar design fills a rectangle east and south and stops at water; then
-- retiring one instance removes exactly its entities and nothing next to it.
--
-- The cell: four solar panels and a medium pole, footprint 7 x 6. Growth
-- starts at the region origin; water starts at x = 40 and y = 30, so five
-- columns (x 0..35) and five rows (y 0..30) fit: 25 instances.

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "fill" }

local REGION = 4
local CELL = {
  { name = "solar-panel", position = { x = 1.5, y = 1.5 } },
  { name = "solar-panel", position = { x = 4.5, y = 1.5 } },
  { name = "solar-panel", position = { x = 1.5, y = 4.5 } },
  { name = "solar-panel", position = { x = 4.5, y = 4.5 } },
  { name = "medium-electric-pole", position = { x = 6.5, y = 3.5 } },
}
local COLUMNS, ROWS = 5, 5

local function origin() return rig.region(REGION) end

function case.setup(surface)
  local o = origin()
  rig.floor(surface, rig.box(o, -80, -80, 80, 80))
  rig.water(surface, rig.box(o, 40, -10, 60, 50))
  rig.water(surface, rig.box(o, -10, 30, 60, 50))
  rig.network(surface, rig.offset(o, -20, -20))
  storage.fill = { design = rig.design(CELL, "Solar cell") }
end

function case.start(surface)
  local o = origin()
  local project, reason = rig.call("start_project", {
    force = rig.FORCE, surface = surface, design = storage.fill.design,
    area = rig.box(o, 0, 0, 100, 100), charted_only = false,
  })
  check.truthy("fill starts", project, reason)
  storage.fill.project = project
end

local function cell_box(col, row)
  local o = origin()
  return rig.box(o, col * 7, row * 6, col * 7 + 7, row * 6 + 6)
end

local function grown(surface)
  local p = rig.call("get_project", storage.fill.project)
  check.eq("fill finished", p and p.state, "finished")
  check.eq("fill instance count", p and p.count, COLUMNS * ROWS)
  check.truthy("fill closed at water", p and (p.closed.water or 0) >= COLUMNS + ROWS - 1, check.show(p and p.closed))
  local o = origin()
  local field = rig.box(o, 0, 0, COLUMNS * 7, ROWS * 6)
  check.eq("fill panels built", rig.count(surface, field, "solar-panel"), COLUMNS * ROWS * 4)
  check.eq("fill poles built", rig.count(surface, field, "medium-electric-pole"), COLUMNS * ROWS)
  check.eq("fill no ghosts left", rig.ghosts(surface, field), 0)
  check.eq("fill nothing on the water", rig.count(surface, rig.box(o, 35, 0, 60, 50), "solar-panel")
    + rig.count(surface, rig.box(o, 0, 30, 35, 50), "solar-panel"), 0)
  -- The middle cell: find its instance by position, then retire it.
  local middle = cell_box(2, 2)
  for id = 1, 5000 do
    local inst = rig.call("get_instance", id)
    if inst and inst.project_id == storage.fill.project
      and inst.footprint.left == middle.left and inst.footprint.top == middle.top then
      storage.fill.middle = id
    end
  end
  check.truthy("fill middle instance found", storage.fill.middle)
  if not storage.fill.middle then return end
  local ok, reason = rig.call("remove_instance", storage.fill.middle)
  check.truthy("fill retire accepted", ok, reason)
end

local function retired(surface)
  local id = storage.fill.middle
  if not id then return end
  check.eq("fill retired copy is forgotten", rig.call("get_instance", id), nil)
  local middle = cell_box(2, 2)
  check.eq("fill retired cell is empty", rig.count(surface, middle, "solar-panel")
    + rig.count(surface, middle, "medium-electric-pole"), 0)
  -- Every neighbour keeps everything.
  for _, n in ipairs({ { 1, 2 }, { 3, 2 }, { 2, 1 }, { 2, 3 } }) do
    local box = cell_box(n[1], n[2])
    check.eq("fill neighbour " .. n[1] .. "," .. n[2] .. " keeps its panels", rig.count(surface, box, "solar-panel"), 4)
    check.eq("fill neighbour " .. n[1] .. "," .. n[2] .. " keeps its pole", rig.count(surface, box, "medium-electric-pole"), 1)
  end
  local o = origin()
  check.eq("fill rest of field intact", rig.count(surface, rig.box(o, 0, 0, COLUMNS * 7, ROWS * 6), "solar-panel"),
    (COLUMNS * ROWS - 1) * 4)
end

case.checks = { [4200] = grown, [6000] = retired }

return case
