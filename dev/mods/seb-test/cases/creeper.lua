-- creeper.lua: a miner that creeps along an ore strip and leaves a belt line
-- behind it, grown from two designs. The head is a drill facing west with an
-- ore sensor, a plug on its west edge, a socket forward naming the head and
-- one on its own ground naming the belt piece; the belt piece is three belts
-- carrying west and a pole that powers the next head, with a plug.
--   creep:  with retire_depleted, once a head's ore is gone the next head
--           goes on at once, and its belt socket waits (out of the frontier)
--           until the head is removed; the belt piece then goes down where
--           the head stood. The belts run unbroken from the start to the
--           head mining now, on mined-out ground, and carry its ore home.
--   stays:  without retire_depleted the head never goes, so its belt socket
--           closes as overlaps-parent, as before
--   plans:  a plan mines nothing: with retire_depleted it plans each belt
--           piece over its head, without it they close as before

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "creeper" }

local REGION = 186
local D = defines.direction
local HEADS = 6                  -- the area holds this many heads, 3 tiles each
local ORE_END = 3 * HEADS + 1    -- ore on row y = 1 from x = 0; the last head mines one past its edge
local STAYS_Y, PLAN_Y, PLAN_KEPT_Y = 20, 30, 40
local STOCK = { { "electric-mining-drill", 20 }, { "transport-belt", 60 }, { "medium-electric-pole", 20 } }

local HEAD = {
  { name = "electric-mining-drill", position = { x = 1.5, y = 1.5 }, direction = D.west },
  { name = "seb-sensor", position = { x = 1.5, y = 1.5 } },
  rig.entry(0.5, 1.5, D.east),
  rig.socket(3.5, 1.5, D.east, "Creeper head"),
  rig.socket(2.5, 1.5, D.east, "Creeper belt"),
}

local function belt(x)
  return { name = "transport-belt", position = { x = x, y = 1.5 }, direction = D.west }
end

local BELT = {
  belt(0.5), belt(1.5), belt(2.5), { name = "medium-electric-pole", position = { x = 1.5, y = 0.5 } },
  rig.entry(2.5, 1.5, D.east),
}

-- Power and a sink at the start: the first head drops onto a belt that
-- carries west into a loader and a chest, and its pole powers that head.
local function start_line(surface, o)
  local function make(name, x, y, extra)
    local spec = { name = name, position = { o.x + x, o.y + y }, force = rig.FORCE }
    for k, v in pairs(extra or {}) do spec[k] = v end
    return surface.create_entity(spec)
  end
  local eei = make("electric-energy-interface", -4, -3)
  eei.power_production, eei.electric_buffer_size = 1e9, 1e10
  make("medium-electric-pole", -2.5, -0.5)
  make("transport-belt", -0.5, 1.5, { direction = D.west })
  make("loader-1x1", -1.5, 1.5, { direction = D.west, type = "input" })
  return make("iron-chest", -2.5, 1.5)
end

-- One ore on each tile of the middle row of a line of heads at `y`, from
-- x = 0 to `to` (a drill's ghost is refused without ore under it).
local function ore(surface, y, to)
  local o = rig.region(REGION)
  for x = 0, to - 1 do
    surface.create_entity { name = "iron-ore", position = { o.x + x + 0.5, o.y + y + 1.5 }, amount = 1 }
  end
end

function case.setup(surface)
  local o = rig.region(REGION)
  rig.floor(surface, rig.box(o, -60, -60, 60, 60))
  rig.network(surface, rig.offset(o, -25, -25), STOCK)
  local c = { retired = {} }
  storage.creeper = c
  c.chest = start_line(surface, o)
  ore(surface, 0, ORE_END)
  ore(surface, STAYS_Y, 3)
  ore(surface, PLAN_Y, 3 * HEADS)
  ore(surface, PLAN_KEPT_Y, 3 * HEADS)
  c.head = rig.design(HEAD, "Creeper head")
  c.belt = rig.design(BELT, "Creeper belt")
  check.truthy("creeper designs registered", c.head and c.belt)
end

local function start(y, extra)
  local o = rig.region(REGION)
  local params = {
    force = rig.FORCE, surface = game.surfaces.nauvis, design = storage.creeper.head, charted_only = false,
    area = rig.box(o, 0, y, 3 * HEADS, y + 3),
  }
  for k, v in pairs(extra) do params[k] = v end
  local id, reason = rig.call("start_project", params)
  check.truthy("creeper project starts at y = " .. y, id, reason)
  return id
end

function case.start()
  local c = storage.creeper
  c.creep = start(0, { retire_depleted = true })
  c.stays = start(STAYS_Y, { area = rig.box(rig.region(REGION), 0, STAYS_Y, 3, STAYS_Y + 3) })
  c.plan = start(PLAN_Y, { retire_depleted = true, dry_run = true })
  c.plan_kept = start(PLAN_KEPT_Y, { dry_run = true })
end

-- The overlay's waiting marks ("Waiting for the copy it grows from to be
-- removed") on the creep's row.
local function waiting_marks()
  local box, n = rig.box(rig.region(REGION), -2, -2, 3 * HEADS + 4, 5), 0
  for _, object in pairs(rendering.get_all_objects(rig.REMOTE)) do
    local p = object.type == "text" and object.target.position
    local text = p and object.text
    if type(text) == "table" and text[1] == "seb-reason.parent-retiring" and p.x >= box.left and p.x < box.right
      and p.y >= box.top and p.y < box.bottom then
      n = n + 1
    end
  end
  return n
end

-- A head of the creep removed: its belt socket was waiting for it then,
-- marked and named in the row (the mod frees the socket right after this
-- event); the next head, unpowered, waits for its ore.
function case.on_event(name, payload)
  local c = storage.creeper
  if name ~= "on_instance_retired" or not c or payload.project_id ~= c.creep then return end
  if payload.design_id ~= c.head then return end
  local p = rig.call("get_project", c.creep)
  c.retired[#c.retired + 1] = { id = payload.instance_id, tick = game.tick, awaiting = p and p.awaiting,
    why = p and p.status.reason, marks = waiting_marks() }
end

-- The creep's copies by design, heads in the order they were stamped.
local function copies()
  local c, heads, belts = storage.creeper, {}, {}
  for _, inst in ipairs(rig.instances_of(c.creep)) do
    if inst.design_id == c.head then heads[#heads + 1] = inst end
    if inst.design_id == c.belt then belts[inst.parent] = inst end
  end
  return heads, belts
end

-- How many heads were removed, how many of them have their belt piece on
-- their own ground (the same columns and top row) and how many of those
-- pieces robots have finished.
local function belts_where_heads_stood(heads, belts)
  local retired, placed, built = 0, 0, 0
  for _, head in ipairs(heads) do
    if head.state == "retired" then
      retired = retired + 1
      local piece, h = belts[head.id], head.footprint
      local b = piece and piece.footprint
      if b and b.left == h.left and b.right == h.right and b.top == h.top and b.bottom <= h.bottom then
        placed = placed + 1
        if piece.state == "complete" then built = built + 1 end
      end
    end
  end
  return retired, placed, built
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

-- Every head removed so far had its belt socket waiting for it: counted,
-- named in the row and marked on the map (case.on_event).
local function each_wait_seen()
  local c = storage.creeper
  for _, r in ipairs(c.retired) do
    local seen = r.awaiting == 1 and r.why == "parent-retiring" and r.marks == 1
    if not seen then return false, check.show(c.retired) end
  end
  return #c.retired > 0, check.show(c.retired)
end

local function creeping(surface)
  local c = storage.creeper
  local p = rig.call("get_project", c.creep)
  check.eq("creeper keeps growing", p and p.state, "growing")
  check.eq("creeper no socket closed as overlaps-parent", p and p.closed["overlaps-parent"], nil)
  local heads, belts = copies()
  local retired, placed, built = belts_where_heads_stood(heads, belts)
  check.truthy("creeper several heads advanced and were removed", retired >= 3, retired)
  check.eq("creeper a belt piece stands where each removed head stood", placed, retired)
  check.truthy("creeper belt pieces built but the newest", built >= retired - 1, built)
  check.truthy("creeper each belt socket waited for its head", each_wait_seen())
  -- The next head may be placed already: the one standing first is mining.
  local first = heads[retired + 1]
  check.eq("creeper the head mining now stands past the last belt piece", first and first.footprint.left,
    rig.region(REGION).x + 3 * retired)
  check.truthy("creeper belts unbroken from the start to the head", unbroken(surface, 3 * built - 1))
  check.eq("creeper belts stand on mined-out ground", rig.count(surface,
    rig.box(rig.region(REGION), 0, 0, 3 * built, 3), "iron-ore"), 0)
  check.truthy("creeper later heads' ore reached the start", c.chest.get_item_count("iron-ore") > 4,
    c.chest.get_item_count("iron-ore"))
  check.info("creeper at " .. game.tick .. ": " .. #heads .. " heads, " .. retired .. " removed, " .. built
    .. " belt pieces built, chest " .. c.chest.get_item_count("iron-ore") .. ", removals " .. check.show(c.retired))
end

-- The unpowered head that stays waits for its ore: the ore goes, so its
-- sockets open.
local function mine_out_stays(surface)
  local o = rig.region(REGION)
  local area = { { o.x, o.y + STAYS_Y }, { o.x + 3, o.y + STAYS_Y + 3 } }
  for _, resource in pairs(surface.find_entities_filtered { area = area, name = "iron-ore" }) do resource.deplete() end
end

local function stays_and_plans()
  local c = storage.creeper
  local s = rig.call("get_project", c.stays)
  check.eq("creeper without retire_depleted the belt socket closes as overlaps-parent",
    s and s.closed["overlaps-parent"], 1)
  check.eq("creeper without retire_depleted the head stays", s and s.state, "finished")
  local p = rig.call("get_project", c.plan)
  check.eq("creeper plan: a belt piece planned over each head", p and p.count, 2 * HEADS)
  check.eq("creeper plan: nothing closed as overlaps-parent", p and p.closed["overlaps-parent"], nil)
  local k = rig.call("get_project", c.plan_kept)
  check.eq("creeper plan without retire_depleted: heads only", k and k.count, HEADS)
  check.eq("creeper plan without retire_depleted: belts close as overlaps-parent",
    k and k.closed["overlaps-parent"], HEADS)
end

-- The last head's forward socket leaves the area; the last belt piece goes
-- down once it is removed, and the project ends with the line whole.
local function finished(surface)
  local c = storage.creeper
  local p = rig.call("get_project", c.creep)
  check.eq("creeper ends once the last head is removed", p and p.state, "finished")
  check.eq("creeper every head and belt piece stamped", p and p.count, 2 * HEADS)
  check.eq("creeper ends at the area's edge", p and p.closed["outside-area"], 1)
  check.eq("creeper ended without overlaps-parent", p and p.closed["overlaps-parent"], nil)
  check.eq("creeper every head removed", #c.retired, HEADS)
  check.truthy("creeper every belt socket waited for its head, named and marked", each_wait_seen())
  check.eq("creeper no waiting mark left", waiting_marks(), 0)
  check.truthy("creeper finished line unbroken", unbroken(surface, 3 * HEADS - 1))
  check.eq("creeper every ore carried home", c.chest.get_item_count("iron-ore"), ORE_END)
  check.eq("creeper no drill left", rig.count(surface, rig.box(rig.region(REGION), 0, 0, 3 * HEADS + 3, 3),
    "electric-mining-drill"), 0)
end

case.checks = { [1200] = mine_out_stays, [1800] = stays_and_plans, [4800] = creeping, [11400] = finished }

return case
