-- dry_drills.lua: a copy is built without the drills that have nothing to
-- mine, as a hand paste leaves them out, and a pool hands growth back to
-- its miner once there is ore again.
--   some:  two drills, ore in reach of one: the copy goes down with that
--          drill alone, finishes, and the network is asked for one drill
--   none:  no ore in reach of either: the spot closes as no-resource
--   pool:  a miner and a belt piece in one book, each with a socket naming
--          the book, over ore, a gap and ore again: miner, belt, belt, miner

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "dry_drills" }

local REGION = 200
local D = defines.direction
local NONE_Y, POOL_Y = 10, 20
-- One drill only: a copy that waited for two would never be built.
local STOCK = { { "electric-mining-drill", 1 }, { "transport-belt", 40 } }
local POOL_STOCK = { { "electric-mining-drill", 4 }, { "transport-belt", 40 } }

local function drill(x)
  return { name = "electric-mining-drill", position = { x = x, y = 1.5 }, direction = D.north }
end

-- Two drills whose mining areas (5 by 5) share one column only.
local PAIR = { drill(1.5), drill(5.5) }

local MINER = { drill(1.5), rig.entry(0.5, 1.5, D.east), rig.socket(3.5, 1.5, D.east, "Dry pool") }

local function belt(x)
  return { name = "transport-belt", position = { x = x, y = 1.5 }, direction = D.west }
end

local BELT = { belt(0.5), belt(1.5), belt(2.5), rig.entry(0.5, 1.5, D.east), rig.socket(3.5, 1.5, D.east, "Dry pool") }

local function ore(surface, x, y)
  local o = rig.region(REGION)
  surface.create_entity { name = "iron-ore", position = { o.x + x + 0.5, o.y + y + 1.5 }, amount = 1000 }
end

-- A labelled book of blueprints, as an export string.
local function book(label, blueprints)
  local inventory = game.create_inventory(1)
  local stack = inventory[1]
  stack.set_stack { name = "blueprint-book" }
  stack.label = label
  local inner = stack.get_inventory(defines.inventory.item_main)
  for i, entry in ipairs(blueprints) do
    inner.insert { name = "blueprint" }
    inner[i].import_stack(rig.blueprint(entry[2], { label = entry[1] }))
  end
  local text = stack.export_stack()
  inventory.destroy()
  return text
end

function case.setup(surface)
  local o = rig.region(REGION)
  rig.floor(surface, rig.box(o, -60, -60, 60, 60))
  rig.network(surface, rig.offset(o, -25, -25), STOCK)
  rig.network(surface, rig.offset(o, -25, 30), POOL_STOCK)
  local s = {}
  storage.dry_drills = s
  -- In reach of the first drill of the pair (columns -1 to 3), not the second (3 to 7).
  ore(surface, 0, 0)
  -- The pool's row: ore under the first miner, none in reach of the next two spots, ore again.
  ore(surface, 0, POOL_Y)
  ore(surface, 1, POOL_Y)
  ore(surface, 10, POOL_Y)
  ore(surface, 11, POOL_Y)
  s.pair = rig.design(PAIR, "Dry pair")
  s.pool_ids = rig.call("register_design", rig.FORCE, book("Dry pool", { { "Dry miner", MINER }, { "Dry belt", BELT } }))
  check.truthy("dry_drills designs registered", s.pair and s.pool_ids and #s.pool_ids == 2)
end

local function start(design, y, width, extra)
  local params = {
    force = rig.FORCE, surface = game.surfaces.nauvis, design = design, charted_only = false,
    area = rig.box(rig.region(REGION), 0, y, width, y + 3), directions = {},
  }
  for k, v in pairs(extra or {}) do params[k] = v end
  local id, reason = rig.call("start_project", params)
  check.truthy("dry_drills project starts at y = " .. y, id, reason)
  return id
end

function case.start()
  local s = storage.dry_drills
  s.some = start(s.pair, 0, 7)
  s.none = start(s.pair, NONE_Y, 7)
  s.pool = start(s.pool_ids[1], POOL_Y, 12)
end

local function verify(surface)
  local s, o = storage.dry_drills, rig.region(REGION)
  local some = rig.call("get_project", s.some)
  check.eq("dry_drills a copy with ore for one drill is placed", some and some.count, 1)
  check.eq("dry_drills it is built with that drill alone", rig.count(surface, rig.box(o, 0, 0, 7, 3), "electric-mining-drill"), 1)
  check.eq("dry_drills no ghost is left for the dry drill", rig.ghosts(surface, rig.box(o, 0, 0, 7, 3)), 0)
  local copy = rig.instances_of(s.some)[1]
  check.eq("dry_drills the copy is complete", copy and copy.state, "complete")
  check.eq("dry_drills the project finishes", some and some.status.level, "finished")
  local none = rig.call("get_project", s.none)
  check.eq("dry_drills a copy with no ore for any drill is refused", none and none.closed["no-resource"], 1)
  check.eq("dry_drills and nothing of it is placed", none and none.count, 0)
  local order = {}
  for i, inst in ipairs(rig.instances_of(s.pool)) do order[i] = inst.design_id end
  local miner, piece = s.pool_ids[1], s.pool_ids[2]
  check.same("dry_drills the pool goes miner, belt, belt, miner", order, { miner, piece, piece, miner })
end

case.checks = { [1800] = verify }

return case
