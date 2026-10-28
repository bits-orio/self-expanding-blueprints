-- platform.lua (Space Age only): growth on a space platform. There are no
-- robots and no network there: the hub builds ghosts from its own
-- inventory, so the materials gate counts the hub, and a spot is never
-- parked as "no robots reach it".

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "platform" }

local function design()
  local tiles = {}
  for x = 0, 2 do
    for y = 0, 2 do tiles[#tiles + 1] = { name = "space-platform-foundation", position = { x = x, y = y } } end
  end
  return rig.design({ rig.panel(1.5, 1.5) }, "Platform cell", { tiles = tiles })
end

-- The east edge of the starter foundation, at the hub's row.
local function east_edge(surface)
  local right = -math.huge
  for _, tile in pairs(surface.find_tiles_filtered { name = "space-platform-foundation", area = { { -64, -2 }, { 64, 2 } } }) do
    right = math.max(right, tile.position.x)
  end
  return right
end

function case.setup()
  if not script.active_mods["space-age"] then return end
  local force = game.forces[rig.FORCE]
  local platform = force.create_space_platform { name = "seb-test-platform", planet = "nauvis", starter_pack = "space-platform-starter-pack" }
  check.truthy("platform created", platform)
  if not platform then return end
  platform.apply_starter_pack()
  local hub = platform.hub
  check.truthy("platform has a hub", hub)
  local inventory = hub.get_inventory(defines.inventory.hub_main)
  inventory.insert { name = "solar-panel", count = 10 }
  inventory.insert { name = "space-platform-foundation", count = 100 }
  storage.platform = { surface = platform.surface, design = design() }
end

function case.start()
  local p = storage.platform
  if not p then return end
  local x = east_edge(p.surface) + 1
  local id, reason = rig.call("start_project", {
    force = rig.FORCE, surface = p.surface, design = p.design, charted_only = false,
    area = { left = x, top = -1, right = x + 9, bottom = 2 }, directions = { defines.direction.east }, max_instances = 2,
  })
  check.truthy("platform project starts", id, reason)
  p.project = id
end

local function verify()
  local p = storage.platform
  if not (p and p.project) then return end
  local project = rig.call("get_project", p.project)
  check.truthy("platform project never waits for robots", project and project.parked == 0, project and project.parked)
  check.truthy("platform copies stamped", project and project.count >= 1, project and check.show(project.status))
  local built = p.surface.count_entities_filtered { name = "solar-panel" }
  check.truthy("platform hub built the panels", built >= 1, built)
end

case.checks = { [6000] = verify }

return case
