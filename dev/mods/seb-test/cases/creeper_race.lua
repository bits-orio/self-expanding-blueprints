-- creeper_race.lua: the creeper on a strip three ores deep, one ore a tile,
-- so each head mines 12 ores, one every 120 ticks. Its drill look comes 600
-- ticks after it is queued, five ores on, so it falls on the tick the
-- head's last ore goes. A copy found dry less than an ore look after its
-- last ore went must still open its sockets before it retires
-- (depletion.lua); without that the line stopped at its first head.

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "creeper_race" }

local REGION = 187
local D = defines.direction
local LENGTH = 21
local STOCK = { { "electric-mining-drill", 20 }, { "transport-belt", 60 }, { "medium-electric-pole", 20 } }

local HEAD = {
  { name = "electric-mining-drill", position = { x = 1.5, y = 1.5 }, direction = D.west },
  { name = "seb-sensor", position = { x = 1.5, y = 1.5 } },
  rig.entry(0.5, 1.5, D.east),
  rig.socket(3.5, 1.5, D.east, "Race head"),
  rig.socket(2.5, 1.5, D.east, "Race belt"),
}

local function belt(x)
  return { name = "transport-belt", position = { x = x, y = 1.5 }, direction = D.west }
end

local BELT = {
  belt(0.5), belt(1.5), belt(2.5), { name = "medium-electric-pole", position = { x = 1.5, y = 0.5 } },
  rig.entry(2.5, 1.5, D.east),
}

function case.setup(surface)
  local o = rig.region(REGION)
  rig.floor(surface, rig.box(o, -60, -60, 60, 60))
  rig.network(surface, rig.offset(o, -25, -25), STOCK)
  rig.line_start(surface, o)
  for x = 0, LENGTH - 1 do
    for y = 0, 2 do
      surface.create_entity { name = "iron-ore", position = { o.x + x + 0.5, o.y + y + 0.5 }, amount = 1 }
    end
  end
  local r = { head = rig.design(HEAD, "Race head"), belt = rig.design(BELT, "Race belt") }
  storage.creeper_race = r
  check.truthy("creeper_race designs registered", r.head and r.belt)
end

function case.start()
  local r = storage.creeper_race
  local id, reason = rig.call("start_project", {
    force = rig.FORCE, surface = game.surfaces.nauvis, design = r.head, charted_only = false,
    area = rig.box(rig.region(REGION), 0, 0, LENGTH, 3), retire_depleted = true,
  })
  check.truthy("creeper_race project starts", id, reason)
  r.project = id
end

local function moved_on()
  local r = storage.creeper_race
  local heads = 0
  for _, inst in ipairs(rig.instances_of(r.project)) do
    if inst.design_id == r.head then heads = heads + 1 end
  end
  local p = rig.call("get_project", r.project)
  local kinds = {}
  for _, e in ipairs(p and p.history or {}) do kinds[#kinds + 1] = e.kind .. "@" .. e.tick end
  check.truthy("creeper_race the line moves on past its 12-ore heads", heads >= 3,
    heads .. " heads; " .. (p and (p.state .. " history " .. table.concat(kinds, " ")) or "no project"))
end

case.checks = { [9000] = moved_on }

return case
