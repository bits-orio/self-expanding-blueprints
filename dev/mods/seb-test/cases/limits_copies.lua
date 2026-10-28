-- limits_copies.lua: forgotten copies, ore looks and research upgrades (regions 90-99).
-- Written by the griefing-mitigation work; see DESIGN.md D43-D45.
--   cycles, forget: a copy is forgotten once retired (its event still names it), at once
--                   when no robot is involved; its project goes on; its number is unknown
--   parent:   a copy retired for depletion stays on record while its project grows (paused
--             counts) and parents the next copy (mining.lua: forgotten once it has ended)
--   looks:    depleted tiles under a waiting copy queue one look of each kind at a time,
--             and the last of them still opens the copy; a pumpjack over oil is never dry,
--             and a resource bigger than a tile whose edge only touches a sensor is not ore
--             left (lithium brine, so with Space Age only)
--   research: a finished research updates every copy of every design naming it, in one pass

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "limits_copies" }

local FORGET, PARENT, LOOKS, RESEARCH, CYCLES, OIL, BRINE = 90, 91, 93, 94, 95, 96, 97
local ORE_LOOK, DRILL_LOOK = 60, 600   -- const.ORE_CHECK_DELAY and const.DRAIN_TICKS
local TECH = "stone-wall"
local STOCK = { { "electric-mining-drill", 10 }, { "iron-chest", 10 }, { "pumpjack", 2 } }

local DRILL = { name = "electric-mining-drill", position = { x = 1.5, y = 1.5 } }   -- mines tiles -1..3
local CHEST = { name = "iron-chest", position = { x = 4.5, y = 1.5 } }
local CHEST_ONE = { name = "iron-chest", position = { x = 0.5, y = 0.5 } }
local SENSOR = { name = "seb-sensor", position = { x = 1.5, y = 1.5 } }               -- on the drill
local TILE_SENSOR = { name = "seb-sensor", position = { x = 0.5, y = 0.5 } }          -- on a chest: its own tile
local PUMP = { name = "pumpjack", position = { x = 1.5, y = 1.5 } }
local V1 = { rig.panel(1.5, 1.5) }
local V2 = { rig.panel(1.5, 1.5), rig.panel(4.5, 1.5) }

-- Calls fn(position of the tile's centre) for the whole tiles left..right-1, top..bottom-1 from the origin.
local function each_tile(o, left, top, right, bottom, fn)
  for x = left, right - 1 do
    for y = top, bottom - 1 do fn({ o.x + x + 0.5, o.y + y + 0.5 }) end
  end
end

local function ore(surface, o, left, top, right, bottom)
  each_tile(o, left, top, right, bottom, function(at)
    surface.create_entity { name = "iron-ore", position = at, amount = 50 }
  end)
end

-- Depletes those tiles' ore one by one: an on_resource_depleted for each.
local function deplete(surface, o, left, top, right, bottom)
  each_tile(o, left, top, right, bottom, function(at)
    local resource = surface.find_entities_filtered { position = at, name = "iron-ore" }[1]
    if resource then resource.deplete() end
  end)
end

-- Ore under the first copy's drill and its whole mining area, and under the next one's.
local function mining_site(surface, region)
  local o = rig.region(region)
  rig.floor(surface, rig.box(o, -60, -60, 60, 60))
  rig.network(surface, rig.offset(o, -25, -25), STOCK)
  ore(surface, o, -1, -1, 4, 4)
  ore(surface, o, 5, 0, 8, 3)
end

local function start(design, region, extra)
  local o = rig.region(region)
  local params = { force = rig.FORCE, surface = game.surfaces.nauvis, design = design, charted_only = false,
    area = rig.box(o, 0, 0, 40, 4) }
  for k, v in pairs(extra) do params[k] = v end
  local id, reason = rig.call("start_project", params)
  check.truthy("limits_copies project starts", id, reason)
  return id
end

local function inst(id) return id and rig.call("get_instance", id) or nil end
local function project(id) return rig.call("get_project", id) or {} end
local function first_of(project_id) return rig.instances_of(project_id)[1] or {} end

function case.setup(surface)
  local s = {}
  storage.limits_copies = s
  rig.site(surface, FORGET)
  for _, region in ipairs({ PARENT, LOOKS }) do mining_site(surface, region) end
  -- A big resource: oil on the pumpjack's tile; brine (finite) just off a sensor's tile.
  for _, big in ipairs({ { OIL, "crude-oil", 1.5 }, { BRINE, "lithium-brine", -0.5 } }) do
    local o = rig.region(big[1])
    rig.floor(surface, rig.box(o, -60, -60, 60, 60))
    rig.network(surface, rig.offset(o, -25, -25), STOCK)
    if prototypes.entity[big[2]] then
      surface.create_entity { name = big[2], position = { o.x + 1.5, o.y + big[3] }, amount = 300000 }
    end
  end
  rig.site(surface, RESEARCH)
  rig.floor(surface, rig.box(rig.region(CYCLES), -10, -10, 60, 30))
  s.cell = rig.design({ rig.panel(1.5, 1.5) }, "Copies cell")
  s.miner = rig.design({ DRILL, CHEST }, "Copies miner")
  s.waiter = rig.design({ DRILL, CHEST, SENSOR }, "Copies waiter")
  s.pump = rig.design({ PUMP }, "Copies pump")
  s.tile = rig.design({ CHEST_ONE, TILE_SENSOR }, "Copies tile")
  s.research = {}
  for i = 1, 3 do s.research[i] = { design = rig.design(V1, "Copies research " .. i), copies = {} } end
end

-- Stamps and removes copies before any robot is near them.
local function cycles(surface, s)
  local o, ids, gone = rig.region(CYCLES), {}, 0
  for i = 0, 29 do
    local at = rig.offset(o, (i % 10) * 4, math.floor(i / 10) * 4)
    local id = rig.call("stamp", { force = rig.FORCE, surface = surface, design = s.cell, position = at })
    if id then
      ids[#ids + 1] = id
      rig.call("remove_instance", id)
      if not inst(id) then gone = gone + 1 end
    end
  end
  check.same("limits_copies thirty copies removed before the robots came leave no record", { #ids, gone }, { 30, 30 })
  check.same("limits_copies a forgotten copy cannot be removed again",
    { rig.call("remove_instance", ids[1]) }, { false, "unknown-instance" })
  check.same("limits_copies a forgotten copy cannot be updated", { rig.call("update_instance", ids[1]) }, { false, "unknown-instance" })
end

-- Copies of three designs in a grid, eight tiles apart.
local function research_copies(surface, s)
  local o = rig.region(RESEARCH)
  local function stamp(r, col, row)
    local at = rig.offset(o, 0.5 + col * 8, 0.5 + row * 8)
    return rig.call("stamp", { force = rig.FORCE, surface = surface, design = r.design, position = at })
  end
  local a, b, c = s.research[1], s.research[2], s.research[3]
  for col = 0, 2 do a.copies[#a.copies + 1] = stamp(a, col, 0) end
  for col = 0, 1 do b.copies[#b.copies + 1] = stamp(b, col, 1) end
  c.copies[1] = stamp(c, 2, 1)
end

function case.start(surface)
  local s = storage.limits_copies
  s.completed, s.retired_events = 0, 0
  s.remove_project = start(s.cell, FORGET, { max_instances = 5 })
  s.parent_project = start(s.miner, PARENT, { max_instances = 2, retire_depleted = true })
  s.looks_project = start(s.waiter, LOOKS, { max_instances = 3, retire_depleted = true })
  s.oil_project = start(s.pump, OIL, { max_instances = 1, retire_depleted = true })
  s.brine_project = prototypes.entity["lithium-brine"] and start(s.tile, BRINE, { max_instances = 2 })
  cycles(surface, s)
  research_copies(surface, s)
end

function case.on_event(name, payload)
  local s = storage.limits_copies
  if not (s and s.remove_project) then return end
  if name == "on_instance_completed" and payload.project_id == s.remove_project then
    s.completed = s.completed + 1
    if s.completed == 2 then   -- the first goes as the second is finished, the project still growing
      local first = first_of(s.remove_project)
      s.removed, s.removed_box = first.id, first.footprint
      rig.call("remove_instance", first.id)
    end
  elseif name == "on_instance_completed" and payload.project_id == s.parent_project and not s.parent_seed then
    s.parent_seed = payload.instance_id
    rig.call("pause_project", payload.project_id)
  elseif name == "on_instance_retired" and payload.instance_id == s.removed then
    s.retired_events = s.retired_events + 1
    s.seen_in_event = (inst(payload.instance_id) or {}).state
  end
end

-- Runs several scenarios' steps at one check tick.
local function together(...)
  local steps = { ... }
  return function(surface)
    for _, step in ipairs(steps) do step(surface) end
  end
end

-- The first copy mines out; its drill's look comes 600 ticks on.
local function mine_out_first_copy(surface)
  local s = storage.limits_copies
  deplete(surface, rig.region(PARENT), -1, -1, 4, 4)
  s.oil_copy = first_of(s.oil_project).id
end

-- Nine tiles of the waiting copy's 5 x 5 area: nine events, one look of each kind.
local function first_run_of_tiles(surface)
  local s = storage.limits_copies
  local waiting = first_of(s.looks_project)
  s.waiting = waiting.id
  check.same("limits_copies a copy waiting for ore has no look queued",
    { waiting.waiting_ore, waiting.ore_check_tick, waiting.drill_check_tick }, { true, nil, nil })
  deplete(surface, rig.region(LOOKS), -1, -1, 2, 2)
  local after, now = inst(s.waiting) or {}, game.tick
  check.same("limits_copies nine depleted tiles queue one look of each kind",
    { after.ore_check_tick, after.drill_check_tick }, { now + ORE_LOOK, now + DRILL_LOOK })
end

-- Six more, a minute on: the ore look has been made, the drills' look has not.
local function second_run_of_tiles(surface)
  local s = storage.limits_copies
  local before = inst(s.waiting) or {}
  check.same("limits_copies the first look found ore left and is not queued any more",
    { before.ore_check_tick, before.waiting_ore }, { nil, true })
  deplete(surface, rig.region(LOOKS), 2, -1, 4, 2)
  local after = inst(s.waiting) or {}
  check.same("limits_copies later tiles queue a look only where none is queued",
    { after.ore_check_tick, after.drill_check_tick }, { game.tick + ORE_LOOK, before.drill_check_tick })
end

-- Both looks found ore left; the rest of it goes.
local function last_run_of_tiles(surface)
  local s = storage.limits_copies
  local waiting = inst(s.waiting) or {}
  check.same("limits_copies the drills' look found ore left and the copy stays",
    { waiting.drill_check_tick, waiting.state, waiting.waiting_ore }, { nil, "complete", true })
  deplete(surface, rig.region(LOOKS), -1, -1, 4, 4)
end

local function copy_opened()
  local s = storage.limits_copies
  check.eq("limits_copies the last depleted tile still opens the copy", (inst(s.waiting) or {}).waiting_ore, false)
  check.eq("limits_copies ... and the next copy comes", project(s.looks_project).count, 2)
end

-- The paused project's copy is out of ore and gone from the map, yet on record.
local function parent_kept()
  local s = storage.limits_copies
  local seed = inst(s.parent_seed) or {}
  check.eq("limits_copies a copy retired for depletion stays on record while its project is paused", seed.state, "retired")
  check.eq("limits_copies ... and the paused project has not grown", project(s.parent_project).count, 1)
  s.parent_box = seed.footprint
  rig.call("resume_project", s.parent_project)
end

-- Neither a pumpjack on its oil nor a chest beside the brine's edge is out of ore.
local function big_resources()
  local s = storage.limits_copies
  check.eq("limits_copies a pumpjack over oil is never dry", (inst(s.oil_copy) or {}).state, "complete")
  if s.brine_project then
    check.eq("limits_copies brine whose centre is off the sensor's tile is not ore left", project(s.brine_project).count, 2)
  end
end

local function parent_grew()
  local s = storage.limits_copies
  local p, child = project(s.parent_project), nil
  for _, copy in ipairs(rig.instances_of(s.parent_project)) do
    if copy.parent == s.parent_seed then child = copy end
  end
  check.eq("limits_copies the retired copy parents the next one", p.count, 2)
  check.eq("limits_copies ... whose sockets did not close", p.closed["parent-retired"], nil)
  check.same("limits_copies ... and it stands beside the retired copy",
    child and { child.footprint.left, child.state }, { s.parent_box.right, "complete" })
  check.same("limits_copies once that project finishes, its copy retired for depletion is forgotten",
    { p.state, inst(s.parent_seed) }, { "finished", nil })
  -- The waiting copy mined out at 1260 and went; its project still waits for the next copy's ore.
  check.eq("limits_copies a copy retired for depletion stays on record while its project grows",
    (inst(s.waiting) or {}).state, "retired")
end

-- Version 2 of all three designs; the first two name the research, the third does not.
local function research_trigger()
  local s = storage.limits_copies
  local registered, named = {}, {}
  for i = 1, 3 do
    registered[i] = rig.call("register_design", rig.FORCE, rig.blueprint(V2, { label = "Copies research " .. i }))
  end
  for i = 1, 2 do named[i] = rig.call("set_upgrade_research", rig.FORCE, s.research[i].design, TECH) end
  check.same("limits_copies the next versions are registered",
    { registered, named }, { { s.research[1].design, s.research[2].design, s.research[3].design }, { true, true } })
  game.forces[rig.FORCE].technologies[TECH].researched = true
end

local function versions(copies)
  local list = {}
  for i, id in ipairs(copies) do list[i] = (inst(id) or {}).version end
  return list
end

local function research_done(surface)
  local s = storage.limits_copies
  check.same("limits_copies research updates every copy of the first design", versions(s.research[1].copies), { 2, 2, 2 })
  check.same("limits_copies ... and of the second, in the same pass", versions(s.research[2].copies), { 2, 2 })
  check.same("limits_copies ... but not of a design that does not name it", versions(s.research[3].copies), { 1 })
  check.eq("limits_copies ... and robots built the new parts",
    rig.count(surface, rig.box(rig.region(RESEARCH), -1, -1, 40, 20), "solar-panel"), 11)
end

local function removed_gone(surface)
  local s = storage.limits_copies
  local p = project(s.remove_project)
  check.same("limits_copies a project goes on after one of its copies is removed", { p.state, p.count }, { "finished", 5 })
  check.eq("limits_copies a removed copy is forgotten once retired", inst(s.removed), nil)
  check.eq("limits_copies the records follow the copies", #rig.instances_of(s.remove_project), p.count - 1)
  check.eq("limits_copies exactly that copy went", rig.count(surface, s.removed_box, "solar-panel"), 0)
  check.eq("limits_copies ... the others stayed",
    rig.count(surface, rig.box(rig.region(FORGET), -1, -1, 40, 4), "solar-panel"), 4)
  check.same("limits_copies its event came once, with its record still there", { s.retired_events, s.seen_in_event }, { 1, "retired" })
end

case.checks = {
  [600] = together(mine_out_first_copy, first_run_of_tiles), [720] = second_run_of_tiles, [1200] = research_trigger,
  [1260] = last_run_of_tiles, [1380] = copy_opened, [1800] = together(parent_kept, big_resources),
  [2400] = together(removed_gone, research_done), [3000] = parent_grew,
}

return case
