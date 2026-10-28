-- options.lua: project order, rules and the admins' map settings.
--   depth:     depth-first growth runs one arm out before the next
--   radius:    copies stay within the radius of the seed
--   enemies:   a spot too close to an enemy building closes as "enemies"
--   landfill:  with landfill off, a design that brings landfill still
--              refuses water
--   early:     a fast fill (sockets open when a copy is placed) fills the
--              same area with the same number of copies

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "options" }

local DEPTH_REGION, RADIUS_REGION, ENEMY_REGION, LANDFILL_REGION = 46, 47, 48, 49
local D = defines.direction
local CELL = { rig.panel(1.5, 1.5) }

local function start(design, region, extra)
  local params = {
    force = rig.FORCE, surface = game.surfaces.nauvis, design = design, charted_only = false,
    build_position = rig.offset(rig.region(region), 0, 0), directions = { D.east, D.south },
  }
  for k, v in pairs(extra or {}) do params[k] = v end
  if params.area then params.build_position = nil end
  local id, reason = rig.call("start_project", params)
  return id, reason
end

function case.setup(surface)
  for _, region in ipairs({ DEPTH_REGION, RADIUS_REGION, ENEMY_REGION, LANDFILL_REGION }) do rig.site(surface, region) end
  local e = rig.region(ENEMY_REGION)
  surface.create_entity { name = "biter-spawner", position = { e.x + 12, e.y + 1 }, force = "enemy" }
  local w = rig.region(LANDFILL_REGION)
  rig.water(surface, rig.box(w, -2, -2, 8, 8))
  local tiles = {}
  for x = 0, 2 do
    for y = 0, 2 do tiles[#tiles + 1] = { name = "landfill", position = { x = x, y = y } } end
  end
  storage.options = {
    cell = rig.design(CELL, "Options cell"),
    landfilled = rig.design(CELL, "Options landfilled", { tiles = tiles }),
  }
end

function case.start()
  local o = storage.options
  -- One copy in flight, so each pick sees the sockets the last copy opened.
  o.depth = start(o.cell, DEPTH_REGION, { order = "depth", max_instances = 3, max_building = 1 })
  o.radius = start(o.cell, RADIUS_REGION, { radius = 7 })
  o.enemy = start(o.cell, ENEMY_REGION, { enemy_distance = 8, directions = { D.east } })
  o.no_landfill = start(o.landfilled, LANDFILL_REGION, { landfill = false, max_instances = 1 })
  o.early = start(o.cell, DEPTH_REGION, {
    open_early = true, max_building = 6, area = rig.box(rig.region(DEPTH_REGION), 0, 20, 9, 29),
  })
  check.truthy("options projects start", o.depth and o.radius and o.enemy and o.no_landfill)
end

local function verify()
  local o = storage.options
  local copies = rig.instances_of(o.depth)
  check.eq("options depth grew three", #copies, 3)
  local seed, third = copies[1], copies[3]
  check.truthy("options depth ran one arm out (third copy south of the seed, same column)",
    seed and third and seed.footprint.left == third.footprint.left and third.footprint.top > seed.footprint.bottom,
    third and check.show(third.footprint))
  local r = rig.call("get_project", o.radius)
  check.truthy("options radius keeps the field small", r and r.count >= 1 and r.count <= 9, r and r.count)
  check.truthy("options radius closes outside", r and (r.closed["outside-area"] or 0) > 0)
  local e = rig.call("get_project", o.enemy)
  check.truthy("options enemy distance closes near the spawner", e and (e.closed.enemies or 0) > 0)
  local l = rig.call("get_project", o.no_landfill)
  check.eq("options no landfill refuses water", l and l.count, 0)
  check.eq("options no landfill reason", l and l.closed.water, 1)
  local none = l and l.nothing_built
  check.eq("options no landfill says why nothing was built", none and none.reason, "water")
  check.truthy("options no landfill says where", none and none.position and none.position.x, none and check.show(none))
  local e2 = rig.call("get_project", o.early)
  check.eq("options fast fill fills the area", e2 and e2.count, 9)
  check.eq("options fast fill finishes", e2 and e2.state, "finished")
end

case.checks = { [1800] = verify }

return case
