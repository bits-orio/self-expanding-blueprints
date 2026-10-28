-- mining.lua: copies that wait for their ore, and copies that go with it.
--   sensor on a drill:  a finished copy opens its sockets only once no ore is
--                       left in the drill's mining area; mining it out (here:
--                       depleting it) lets the next copy come
--   sensor radius:      a sensor with R = 0 watches its own tile only
--   retire depleted:    with the option on, a copy whose drills have nothing
--                       left to mine retires
--   review fixes:       a waiting copy that is removed lets its project
--                       finish; a copy whose drills are all destroyed is not
--                       "dry"; crude oil next to a sensor is not ore left;
--                       a huge R is clamped

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "mining" }

local CHAIN_REGION, TILE_REGION, RETIRE_REGION = 34, 35, 36
local REMOVED_REGION, NO_DRILL_REGION, OIL_REGION, HUGE_REGION, STOPPED_REGION = 41, 42, 43, 44, 50
local D = defines.direction
local STOCK = { { "electric-mining-drill", 10 }, { "iron-chest", 10 } }

local DRILL = { name = "electric-mining-drill", position = { x = 1.5, y = 1.5 } }   -- tiles 0..3
local CHEST = { name = "iron-chest", position = { x = 4.5, y = 1.5 } }               -- bounds reach x = 5

local function sensor(x, y, radius)
  local e = { name = "seb-sensor", position = { x = x, y = y } }
  if radius then
    e.control_behavior = { sections = { sections = { { index = 1, filters = {
      { index = 1, type = "virtual", name = "signal-R", quality = "normal", comparator = "=", count = radius },
    } } } } }
  end
  return e
end

local function ore(surface, o, left, top, right, bottom, amount)
  for x = left, right - 1 do
    for y = top, bottom - 1 do
      surface.create_entity { name = "iron-ore", position = { o.x + x + 0.5, o.y + y + 0.5 }, amount = amount or 50 }
    end
  end
end

local function deplete(surface, o, left, top, right, bottom)
  local area = { { o.x + left, o.y + top }, { o.x + right, o.y + bottom } }
  for _, resource in pairs(surface.find_entities_filtered { area = area, name = "iron-ore" }) do resource.deplete() end
end

local function site(surface, region)
  local o = rig.region(region)
  rig.floor(surface, rig.box(o, -60, -60, 60, 60))
  rig.network(surface, rig.offset(o, -25, -25), STOCK)
  -- Ore under the first copy's drill and under the next one's.
  ore(surface, o, 0, 0, 3, 3)
  ore(surface, o, 5, 0, 8, 3)
  return o
end

function case.setup(surface)
  for _, region in ipairs({ CHAIN_REGION, TILE_REGION, RETIRE_REGION, REMOVED_REGION, NO_DRILL_REGION, OIL_REGION,
    STOPPED_REGION }) do
    site(surface, region)
  end
  -- Crude oil centred just outside the oil test's sensor tile: its edge
  -- reaches into the tile, but it is neither inside nor finite.
  local oil = rig.region(OIL_REGION)
  surface.create_entity { name = "crude-oil", position = { oil.x + 1.5, oil.y - 0.5 }, amount = 300000 }
  rig.floor(surface, rig.box(rig.region(HUGE_REGION), -10, -10, 10, 10))
  storage.mining = {
    chain = rig.design({ DRILL, CHEST, sensor(1.5, 1.5), rig.socket(5.5, 1.5, D.east) }, "Mining chain"),
    tile = rig.design({ DRILL, CHEST, sensor(0.5, 0.5, 0), rig.socket(5.5, 1.5, D.east) }, "Mining tile"),
    plain = rig.design({ DRILL }, "Mining plain"),
    huge = rig.design({ CHEST, sensor(4.5, 1.5, 100000) }, "Mining huge"),
  }
  -- The lab has no ore, so a drill's ghost is made directly for the picture.
  local gallery = game.get_surface("seb-gallery")
  check.truthy("mining picture shows the drill",
    gallery and gallery.count_entities_filtered { ghost_name = "electric-mining-drill" } > 0)
end

local function start(design, region, extra)
  local o = rig.region(region)
  local params = {
    force = rig.FORCE, surface = game.surfaces.nauvis, design = design, charted_only = false,
    area = rig.box(o, 0, 0, 20, 4), max_instances = 2,
  }
  for k, v in pairs(extra or {}) do params[k] = v end
  local id, reason = rig.call("start_project", params)
  check.truthy("mining project starts", id, reason)
  return id
end

function case.start()
  local m = storage.mining
  m.chain_project = start(m.chain, CHAIN_REGION)
  m.tile_project = start(m.tile, TILE_REGION)
  m.retire_project = start(m.plain, RETIRE_REGION, { max_instances = 1, retire_depleted = true })
  m.removed_project = start(m.chain, REMOVED_REGION, { max_instances = 3 })
  m.no_drill_project = start(m.plain, NO_DRILL_REGION, { max_instances = 1, retire_depleted = true })
  m.oil_project = start(m.tile, OIL_REGION, { max_instances = 3 })
  m.stopped_project = start(m.plain, STOPPED_REGION, { max_instances = 1, retire_depleted = true })
  local huge = rig.call("stamp", {
    force = rig.FORCE, surface = game.surfaces.nauvis, design = m.huge, position = rig.offset(rig.region(HUGE_REGION), 0.5, 0.5),
  })
  local inst = huge and rig.call("get_instance", huge)
  local box = inst and inst.sensors and inst.sensors[1]
  check.eq("mining huge R is clamped", box and (box.right - box.left), 129)
end

local function has(project, kind)
  for _, entry in ipairs(project and project.history or {}) do
    if entry.kind == kind then return true end
  end
  return false
end

local function first_built(surface)
  local m = storage.mining
  local p = rig.call("get_project", m.chain_project)
  check.eq("mining first copy built, next one waits", p and p.count, 1)
  check.eq("mining project waits for the ore", p and p.status.level, "waiting")
  check.eq("mining waiting reason", p and p.status.reason, "ore-left")
  check.truthy("mining history says it waits for ore", has(p, "waiting-ore"))
  local inst = rig.instances_of(m.chain_project)[1]
  check.eq("mining first copy waits for ore", inst and inst.waiting_ore, true)
  m.retire_instance = (rig.instances_of(m.retire_project)[1] or {}).id
  check.same("mining sensor watches the drill's area", inst and inst.sensors and inst.sensors[1],
    rig.box(rig.region(CHAIN_REGION), -1, -1, 4, 4))
  local drawn = rig.drawn(surface, rig.box(rig.region(CHAIN_REGION), -2, -2, 8, 6))
  check.truthy("mining waiting copy drawn", (drawn.rectangle or 0) >= 1 and (drawn.text or 0) >= 1, check.show(drawn))
  local t = rig.call("get_project", m.tile_project)
  check.eq("mining tile sensor waits too", t and t.count, 1)
  -- The tile sensor watches one tile: depleting just it is enough.
  deplete(surface, rig.region(TILE_REGION), 0, 0, 1, 1)
  deplete(surface, rig.region(CHAIN_REGION), -1, -1, 4, 4)
  deplete(surface, rig.region(RETIRE_REGION), -1, -1, 4, 4)
  deplete(surface, rig.region(OIL_REGION), 0, 0, 1, 1)
  -- The waiting copy goes: nothing holds its project open any more.
  local waiting = rig.instances_of(m.removed_project)[1]
  check.eq("mining removed copy was waiting", waiting and waiting.waiting_ore, true)
  if waiting then rig.call("remove_instance", waiting.id) end
  -- Its drill destroyed, a copy is not dry, whatever depletes around it.
  local plain = rig.instances_of(m.no_drill_project)[1]
  local o = rig.region(NO_DRILL_REGION)
  for _, drill in pairs(surface.find_entities_filtered { area = { { o.x, o.y }, { o.x + 3, o.y + 3 } }, name = "electric-mining-drill" }) do
    drill.destroy()
  end
  deplete(surface, o, 0, 0, 1, 1)
  m.no_drill_instance = plain and plain.id
  -- A stopped project removes nothing any more, mined out or not.
  local stopped = rig.instances_of(m.stopped_project)[1]
  m.stopped_instance = stopped and stopped.id
  rig.call("stop_project", m.stopped_project)
  deplete(surface, rig.region(STOPPED_REGION), -1, -1, 4, 4)
end

local function grew_on(surface)
  local m = storage.mining
  local p = rig.call("get_project", m.chain_project)
  check.eq("mining ore gone: the next copy comes", p and p.count, 2)
  check.truthy("mining history says the ore ran out", has(p, "ore-gone"))
  local t = rig.call("get_project", m.tile_project)
  check.eq("mining tile sensor opened on its own tile", t and t.count, 2)
  check.eq("mining ore left beside the tile sensor",
    surface.count_entities_filtered { area = { { rig.region(TILE_REGION).x, rig.region(TILE_REGION).y }, {
      rig.region(TILE_REGION).x + 3, rig.region(TILE_REGION).y + 3 } }, type = "resource" }, 8)
  local r = rig.call("get_project", m.retire_project)
  check.truthy("mining depleted copy goes", has(r, "depleted"))
  local inst = rig.call("get_instance", m.retire_instance)
  check.truthy("mining depleted copy retiring or gone", inst == nil or inst.state == "retiring", inst and inst.state)
  local removed = rig.call("get_project", m.removed_project)
  check.eq("mining removed waiting copy lets the project finish", removed and removed.state, "finished")
  local oil = rig.call("get_project", m.oil_project)
  check.truthy("mining crude oil beside a sensor is not ore left", oil and oil.count >= 2, oil and oil.count)
  local no_drill = m.no_drill_instance and rig.call("get_instance", m.no_drill_instance)
  check.eq("mining copy without drills is not dry", no_drill and no_drill.state, "complete")
  local stopped = m.stopped_instance and rig.call("get_instance", m.stopped_instance)
  check.eq("mining stopped project's dry copy stays", stopped and stopped.state, "complete")
end

local function cleared(surface)
  local m = storage.mining
  check.truthy("mining depleted copy was stamped", m.retire_instance)
  check.eq("mining depleted copy retired, then forgotten (its project is finished)", rig.call("get_instance", m.retire_instance), nil)
  check.eq("mining depleted drill removed",
    rig.count(surface, rig.box(rig.region(RETIRE_REGION), 0, 0, 3, 3), "electric-mining-drill"), 0)
end

case.checks = { [1200] = first_built, [2400] = grew_on, [4200] = cleared }

return case
