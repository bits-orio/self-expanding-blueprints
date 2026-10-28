-- creeper_one.lua: the creeping miner as one design, grown with "Replace
-- buildings in the way" (superforce, D54). Three belts carrying west and a
-- pole at the back, a drill in front dropping onto them with an ore sensor,
-- a plug at the back and a socket on the drill's back edge naming the design
-- itself. Once a drill's ore is gone the next copy lands a drill's length
-- on: superforced, it puts its belts and pole where the old drill stood
-- (the paste marks that drill for removal) and its own drill on fresh ore.
-- Every copy keeps its belts and pole, so the line stays whole, standing on
-- mined-out ground only. The strip is three ores deep, one ore a tile.
--   plain:  without superforce the same design still closes overlaps-parent
--   plan:   a superforced plan plans each copy over the one before
--   twin:   where the next copy wants a part whose twin already stands, the
--           paste keeps that one and the copy is whole; a copy that would
--           place nothing new (its socket on its own plug) is refused
--   remove: removing a copy takes only what it still has

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "creeper_one" }

local REGION = 188
local D = defines.direction
local NAME = "Creeping miner"
local COPIES = 5                              -- the area holds this many, each 3 tiles past the last
local ORE_FROM, ORE_TO = 3, 3 * COPIES + 4    -- columns under the drills; the last mines one past its edge
local PLAIN_Y, PLAN_Y, TWIN_Y, SAME_Y = 20, 30, 10, 14   -- robots reach y < 30; a plan needs none
local STOCK = {
  { "electric-mining-drill", 20 }, { "transport-belt", 60 }, { "medium-electric-pole", 20 }, { "iron-chest", 10 },
}

local function belt(x)
  return { name = "transport-belt", position = { x = x, y = 1.5 }, direction = D.west }
end

local MINER = {
  belt(0.5), belt(1.5), belt(2.5), { name = "medium-electric-pole", position = { x = 1.5, y = 0.5 } },
  { name = "electric-mining-drill", position = { x = 4.5, y = 1.5 }, direction = D.west },
  { name = "seb-sensor", position = { x = 4.5, y = 1.5 } },
  rig.entry(0.5, 1.5, D.east),
  rig.socket(3.5, 1.5, D.east, NAME),
}

-- Two chests two tiles apart; the next copy's first chest lands on this
-- one's second.
local TWIN = {
  { name = "iron-chest", position = { x = 0.5, y = 0.5 } }, { name = "iron-chest", position = { x = 2.5, y = 0.5 } },
  rig.entry(0.5, 0.5, D.east), rig.socket(2.5, 0.5, D.east),
}

-- A chest whose socket sits on its own plug: the next copy would stand
-- exactly on this one.
local SAME = {
  { name = "iron-chest", position = { x = 0.5, y = 0.5 } }, rig.entry(0.5, 0.5, D.east), rig.socket(0.5, 0.5, D.east),
}

-- One ore on every tile of three rows from `y`, under the drills.
local function ore(surface, y)
  local o = rig.region(REGION)
  for x = ORE_FROM, ORE_TO - 1 do
    for dy = 0, 2 do
      surface.create_entity { name = "iron-ore", position = { o.x + x + 0.5, o.y + y + dy + 0.5 }, amount = 1 }
    end
  end
end

-- With the base game the map makes enemy bases around this region (seed 1),
-- and the drills' pollution over a few minutes brings their attacks onto
-- the roboport. rig.prepare kills the units; the bases near here go too.
local function clear_enemies(surface, o)
  for _, e in pairs(surface.find_entities_filtered { position = o, radius = 320, force = "enemy" }) do e.destroy() end
end

function case.setup(surface)
  local o = rig.region(REGION)
  rig.floor(surface, rig.box(o, -60, -60, 60, 60))
  clear_enemies(surface, o)
  rig.network(surface, rig.offset(o, -25, -25), STOCK)
  local c = {}
  storage.creeper_one = c
  c.chest = rig.line_start(surface, o)
  ore(surface, 0)
  ore(surface, PLAN_Y)
  for x = ORE_FROM, ORE_FROM + 2 do
    surface.create_entity { name = "iron-ore", position = { o.x + x + 0.5, o.y + PLAIN_Y + 1.5 }, amount = 1 }
  end
  c.design = rig.design(MINER, NAME)
  c.twin = rig.design(TWIN, "Creeper twin")
  c.same = rig.design(SAME, "Creeper same")
  check.truthy("creeper_one designs registered", c.design and c.twin and c.same)
end

local function start(design, y, extra)
  local params = {
    force = rig.FORCE, surface = game.surfaces.nauvis, design = design, charted_only = false,
    area = rig.box(rig.region(REGION), 0, y, 3 * COPIES + 3, y + 3),
  }
  for k, v in pairs(extra) do params[k] = v end
  local id, reason = rig.call("start_project", params)
  check.truthy("creeper_one project starts at y = " .. y, id, reason)
  return id
end

function case.start()
  local c = storage.creeper_one
  c.project = start(c.design, 0, { superforce = true })
  c.plain = start(c.design, PLAIN_Y, {})
  c.plan = start(c.design, PLAN_Y, { superforce = true, dry_run = true })
  c.twin_project = start(c.twin, TWIN_Y, { superforce = true, max_instances = 3 })
  c.same_project = start(c.same, SAME_Y, { superforce = true })
end

-- Belts facing west on row y = 1 from x = -1 (the start's) to x = last.
local function unbroken(surface, last)
  local o = rig.region(REGION)
  for x = -1, last do
    local found = surface.find_entity("transport-belt", { o.x + x + 0.5, o.y + 1.5 })
    if not (found and found.direction == D.west) then return false, x end
  end
  return true
end

-- Of the copies whose next copy is built (`done`), how many kept their
-- three belts and pole and lost their drill to it, still on record as
-- complete with those four parts (`kept`).
local function steps(surface, list)
  local o, done, kept = rig.region(REGION), 0, 0
  for i = 1, #list - 1 do
    if list[i + 1].state == "complete" then
      done = done + 1
      local copy, left = list[i], list[i].footprint.left - o.x
      local belts = rig.count(surface, rig.box(o, left, 1, left + 3, 2), "transport-belt")
      local poles = rig.count(surface, rig.box(o, left, 0, left + 3, 1), "medium-electric-pole")
      local drills = rig.count(surface, rig.box(o, left + 3, 0, left + 6, 3), "electric-mining-drill")
      if belts == 3 and poles == 1 and drills == 0 and copy.state == "complete" and copy.entity_count == 4 then
        kept = kept + 1
      end
    end
  end
  return done, kept
end

-- The plain head mines nothing (no power): its ore goes, so its socket opens.
local function mine_out_plain(surface)
  local o = rig.region(REGION)
  local area = { { o.x, o.y + PLAIN_Y }, { o.x + 6, o.y + PLAIN_Y + 3 } }
  for _, resource in pairs(surface.find_entities_filtered { area = area, name = "iron-ore" }) do resource.deplete() end
end

local function plain_plan_twin(surface)
  local c, o = storage.creeper_one, rig.region(REGION)
  local plain = rig.call("get_project", c.plain)
  check.same("creeper_one without superforce the copy closes as overlaps-parent",
    plain and { plain.count, plain.closed["overlaps-parent"], plain.state }, { 1, 1, "finished" })
  local p = rig.call("get_project", c.plan)
  check.same("creeper_one a superforced plan plans each copy over the one before",
    p and { p.count, p.closed["overlaps-parent"], p.closed["outside-area"] }, { COPIES, nil, 1 })
  local t = rig.call("get_project", c.twin_project)
  check.same("creeper_one a part whose twin stands is kept: every copy whole",
    t and { t.count, t.closed["stamp-short"], t.building }, { 3, nil, 0 })
  check.eq("creeper_one the twin copies share their chests", rig.count(surface, rig.box(o, 0, TWIN_Y, 10, TWIN_Y + 1),
    "iron-chest"), 4)
  local same = rig.call("get_project", c.same_project)
  check.same("creeper_one a copy that would place nothing new is refused",
    same and { same.state, same.count, same.closed["stamp-short"] }, { "finished", 1, 1 })
end

local function creeping(surface)
  local c, o = storage.creeper_one, rig.region(REGION)
  local p = rig.call("get_project", c.project)
  check.eq("creeper_one keeps growing", p and p.state, "growing")
  check.eq("creeper_one no socket closed as overlaps-parent", p and p.closed["overlaps-parent"], nil)
  local list = rig.instances_of(c.project)
  local done, kept = steps(surface, list)
  check.truthy("creeper_one creeps several steps", done >= 3, done)
  check.eq("creeper_one each step's drill replaced, its belts and pole kept", kept, done)
  check.truthy("creeper_one belts unbroken from the start", unbroken(surface, 3 * (done + 1) - 1))
  check.eq("creeper_one nothing but drills stands on ore",
    rig.count(surface, rig.box(o, 0, 0, 3 * (done + 1), 3), "iron-ore"), 0)
  check.truthy("creeper_one later copies' ore reached the start", c.chest.get_item_count("iron-ore") > 12,
    c.chest.get_item_count("iron-ore"))
  check.info("creeper_one at " .. game.tick .. ": " .. #list .. " copies, " .. done .. " steps, chest "
    .. c.chest.get_item_count("iron-ore"))
end

-- The last copy's socket leaves the area; its drill stays (nothing removes
-- a copy that runs dry here). Then the first copy is removed.
local function finished(surface)
  local c, o = storage.creeper_one, rig.region(REGION)
  local p = rig.call("get_project", c.project)
  check.same("creeper_one ends at the area's edge", p and { p.state, p.count, p.closed["outside-area"] },
    { "finished", COPIES, 1 })
  check.same("creeper_one ended without overlaps-parent or a short stamp",
    p and { p.closed["overlaps-parent"], p.closed["stamp-short"] }, {})
  local done, kept = steps(surface, rig.instances_of(c.project))
  check.same("creeper_one every step's drill replaced, its belts and pole kept", { done, kept },
    { COPIES - 1, COPIES - 1 })
  check.eq("creeper_one only the last drill stands", rig.count(surface, rig.box(o, 0, 0, 3 * COPIES + 6, 3),
    "electric-mining-drill"), 1)
  check.truthy("creeper_one the whole line stands, unbroken", unbroken(surface, 3 * COPIES - 1))
  check.eq("creeper_one every copy keeps its pole", rig.count(surface, rig.box(o, 0, 0, 3 * COPIES, 1),
    "medium-electric-pole"), COPIES)
  check.eq("creeper_one every ore carried home", c.chest.get_item_count("iron-ore"), 3 * (ORE_TO - ORE_FROM))
  local first = rig.instances_of(c.project)[1]
  c.first = first and first.id
  check.truthy("creeper_one the first copy is removed", c.first and rig.call("remove_instance", c.first))
end

-- Only what the first copy still had went: the second copy's belts and
-- pole, standing where the first one's drill stood, stay.
local function removed(surface)
  local c, o = storage.creeper_one, rig.region(REGION)
  local function parts(left)
    local box = rig.box(o, left, 0, left + 3, 3)
    return rig.count(surface, box, "transport-belt"), rig.count(surface, box, "medium-electric-pole")
  end
  local first_belts, first_poles = parts(0)
  local next_belts, next_poles = parts(3)
  check.same("creeper_one removing a copy takes only what it still has",
    { first_belts, first_poles, next_belts, next_poles }, { 0, 0, 3, 1 })
  check.eq("creeper_one the removed copy is forgotten", rig.call("get_instance", c.first), nil)
end

case.checks = {
  [1500] = mine_out_plain, [2100] = plain_plan_twin, [6600] = creeping, [10800] = finished, [11400] = removed,
}

return case
