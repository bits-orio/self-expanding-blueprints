-- A first copy must land where the original blueprint lands, even when a
-- marker extends beyond the buildings. The engine centres all entities;
-- centring only the buildable footprint shifts the copy after a Grow click.
-- Compare with the engine in each direction, with and without snap grids.

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "anchor_markers" }
local REGION = 200
local D = defines.direction
local VARIANTS = {
  { name = "plain" },
  { name = "inside", marker = "seb-socket", x = 2.5 },
  { name = "east", marker = "seb-socket", x = 5.5 },
  { name = "west", marker = "seb-socket", x = -2.5 },
  { name = "sensor", marker = "seb-sensor", x = 5.5 },
  { name = "plug", marker = "seb-entry", x = 5.5 },
  { name = "relative", marker = "seb-socket", x = 5.5, grid = { x = 8, y = 8 } },
  { name = "absolute", marker = "seb-socket", x = 5.5, grid = { x = 8, y = 8 }, absolute = { x = 1, y = 2 } },
}

-- The real blueprint's solar panel, excluding its markers, at the same
-- point and direction that will be passed to start_project below.
local function vanilla(surface, text, point, direction)
  local inventory = game.create_inventory(1)
  inventory[1].import_stack(text)
  local ghosts = inventory[1].build_blueprint {
    surface = surface, force = rig.FORCE, position = point, direction = direction,
    build_mode = defines.build_mode.forced,
  }
  local panel
  for _, ghost in pairs(ghosts) do
    if ghost.ghost_name == "solar-panel" then panel = ghost.position end
    ghost.destroy()
  end
  inventory.destroy()
  return panel
end

function case.setup(surface)
  local o = rig.region(REGION)
  rig.floor(surface, rig.box(o, -20, -20, 100, 180))
  storage.anchor_markers = {}
  for row, variant in ipairs(VARIANTS) do
    local entities = { rig.panel(1.5, 1.5) }
    if variant.marker then
      entities[#entities + 1] = {
        name = variant.marker, position = { x = variant.x, y = 1.5 }, direction = D.east,
      }
    end
    local text = rig.blueprint(entities, {
      label = "Anchor markers " .. variant.name, grid = variant.grid, absolute = variant.absolute,
    })
    local design = rig.call("register_design", rig.FORCE, text)
    check.truthy("anchor_markers registers " .. variant.name, design)
    for column, direction in ipairs({ D.north, D.east, D.south, D.west }) do
      local point = rig.offset(o, 20 * column + 0.25, 20 * row + 0.75)
      local expected = vanilla(surface, text, point, direction)
      check.truthy("anchor_markers vanilla " .. variant.name .. " dir " .. direction, expected)
      storage.anchor_markers[#storage.anchor_markers + 1] = {
        design = design, label = variant.name .. " dir " .. direction,
        point = point, direction = direction, expected = expected,
      }
    end
  end
end

function case.start(surface)
  for _, item in ipairs(storage.anchor_markers) do
    local id, why = rig.call("start_project", {
      force = rig.FORCE, surface = surface, design = item.design, charted_only = false,
      point = item.point, direction = item.direction, max_instances = 1, materials = false,
    })
    item.project = id
    check.truthy("anchor_markers starts " .. item.label, id, why)
  end
end

local function verify(surface)
  for _, item in ipairs(storage.anchor_markers) do
    local project = item.project and rig.call("get_project", item.project)
    check.eq("anchor_markers one copy " .. item.label, project and project.count, 1)
    local p = item.point
    local panels = surface.find_entities_filtered {
      area = { { p.x - 10, p.y - 10 }, { p.x + 10, p.y + 10 } },
      type = "entity-ghost", ghost_name = "solar-panel", force = rig.FORCE,
    }
    check.eq("anchor_markers one panel " .. item.label, #panels, 1)
    check.same("anchor_markers matches vanilla " .. item.label, panels[1] and panels[1].position, item.expected)
  end
end

case.checks = { [600] = verify }

return case
