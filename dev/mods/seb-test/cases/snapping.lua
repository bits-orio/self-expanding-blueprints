-- snapping.lua: a blueprint with absolute snapping lands where the player's
-- own blueprint would.
--   anchor:  a click seeds the copy in the world grid cell under it, in all
--            four directions, exactly where vanilla build_blueprint puts the
--            player's blueprint with the cursor there
--   fill:    a drag fills from the first whole grid cell, and every copy
--            sits on the world grid
--   raw:     a copy seeded off the grid by a raw build_position keeps
--            growing flush with its seed, one grid step at a time

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "snapping" }

local REGION = 21
local D = defines.direction
-- A 4x3 design in a 5x4 grid whose lines sit at x = 1 + 5k, y = 2 + 4k.
local GRID, REL = { x = 5, y = 4 }, { x = 1, y = 2 }
local CELL = { rig.panel(1.5, 1.5), { name = "small-electric-pole", position = { x = 3.5, y = 0.5 } } }
local DIRECTIONS = { D.north, D.east, D.south, D.west }

-- Where vanilla puts the player's blueprint with the cursor at `at`.
local function vanilla(surface, text, at, d)
  local inventory = game.create_inventory(1)
  inventory[1].import_stack(text)
  local ghosts = inventory[1].build_blueprint {
    surface = surface, force = rig.FORCE, position = at, direction = d, build_mode = defines.build_mode.forced,
  }
  inventory.destroy()
  local box = rig.tiles_of(ghosts)
  for _, ghost in pairs(ghosts) do ghost.destroy() end
  return box
end

local function start(design, extra)
  local params = { force = rig.FORCE, surface = game.surfaces.nauvis, design = design, charted_only = false }
  for k, v in pairs(extra) do params[k] = v end
  local id, reason = rig.call("start_project", params)
  check.truthy("snapping start", id, reason)
  return id
end

function case.setup(surface)
  local o = rig.site(surface, REGION)
  local text = rig.blueprint(CELL, { label = "Snapped cell", grid = GRID, absolute = REL })
  local s = { design = rig.call("register_design", rig.FORCE, text), clicks = {} }
  storage.snapping = s
  for i, d in ipairs(DIRECTIONS) do
    local at = rig.offset(o, 33.3 + 6 * i, 7.7 + 9 * i)
    s.clicks[i] = { want = vanilla(surface, text, at, d), project = start(s.design, {
      point = at, direction = d, max_instances = 1, materials = false,
    }) }
  end
  s.fill = start(s.design, { area = rig.box(o, 0.5, 0.5, 26, 20) })
  -- Two seeds a tile apart: whatever the offsets, one of them is off the grid.
  s.raw = {
    start(s.design, { build_position = rig.offset(o, 1, 22), directions = { D.east }, max_instances = 2 }),
    start(s.design, { build_position = rig.offset(o, 12, 22), directions = { D.east }, max_instances = 2 }),
  }
end

local function on_grid(inst)
  return (inst.footprint.left - REL.x) % GRID.x == 0 and (inst.footprint.top - REL.y) % GRID.y == 0
end

local function verify()
  local s = storage.snapping
  for i, click in ipairs(s.clicks) do
    local inst = rig.instances_of(click.project)[1]
    check.same("snapping click lands like vanilla, direction " .. DIRECTIONS[i], inst and inst.footprint, click.want)
  end
  local list = rig.instances_of(s.fill)
  check.eq("snapping fill count", #list, 20)
  local off = 0
  for _, inst in ipairs(list) do if not on_grid(inst) then off = off + 1 end end
  check.eq("snapping fill copies all on the world grid", off, 0)
  for i, project in ipairs(s.raw) do
    local copies = rig.instances_of(project)
    local a, b = copies[1] and copies[1].footprint, copies[2] and copies[2].footprint
    check.same("snapping raw seed " .. i .. " grows one grid step", b and { b.left - a.left, b.top - a.top }, { GRID.x, 0 })
  end
  local first = list[1] and list[1].footprint
  check.same("snapping fill starts in the first whole cell", first and { first.left, first.top },
    { rig.region(REGION).x + 1, rig.region(REGION).y + 2 })
end

case.checks = { [4200] = verify }

return case
