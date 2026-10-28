-- fix_cliffs.lua: only a cliff under a part stops a copy (regions 101-102).
--   gap:      a cliff between two parts no longer refuses the copy, and is
--             left alone
--   blocked:  without cliff explosives, a cliff under an entity part, a
--             design tile or a Keep clear tile refuses the copy, at the cliff;
--             a plan over one closes its spot "cliff"
--   cleared:  with them (a force of its own), the copy is stamped over each
--             such cliff and the cliff is marked for deconstruction; a plan
--             over one plans the copy and marks nothing
--   rollback: a superforced stamp over a cliff that comes out short is rolled
--             back and leaves the cliff and a tree under another part unmarked

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "fix_cliffs" }

local OFF, ON = 101, 102
local FORCE = "seb-fix-cliffs"

local function chest(x, y) return { name = "wooden-chest", position = { x = x, y = y } } end
-- Each design's entry arrow sits on its first chest: a stamp at a tile puts
-- that chest there.
local ENTRY = { name = "seb-entry", position = { x = 0.5, y = 0.5 }, direction = defines.direction.north }

local DESIGNS = {
  one = { chest(0.5, 0.5), ENTRY },
  gap = { chest(0.5, 0.5), chest(12.5, 0.5), ENTRY },
  tile = { chest(0.5, 0.5), ENTRY },
  kept = { chest(0.5, 0.5), { name = "seb-keep-clear", position = { x = 6.5, y = 0.5 } }, ENTRY },
  trio = { chest(0.5, 0.5), chest(3.5, 0.5), chest(6.5, 0.5), ENTRY },
}
local TILES = { tile = { { name = "stone-path", position = { x = 6, y = 0 } } } }

-- Each case's design, how far its first chest stands from the cliff, and
-- whether that cliff is under a part.
local CASES = {
  { key = "one", shift = 0, under = true },
  { key = "gap", shift = -6, under = false },
  { key = "tile", shift = -6, under = true },
  { key = "kept", shift = -6, under = true },
}

-- The force's design `key`, registered once.
local function design(force, key)
  local ids = storage.fix_cliffs.designs
  ids[force] = ids[force] or {}
  if not ids[force][key] then
    local text = rig.blueprint(DESIGNS[key], { label = "Fix cliffs " .. key .. " " .. force, tiles = TILES[key] })
    ids[force][key] = rig.call("register_design", force, text)
  end
  return ids[force][key]
end

-- A cliff near (x, y), and the centre of a tile it covers (cliffs snap to
-- their own grid).
local function cliff_near(surface, x, y)
  local cliff = surface.create_entity { name = "cliff", position = { x, y }, cliff_orientation = "west-to-east" }
  return cliff, { x = math.floor(cliff.position.x) + 0.5, y = math.floor(cliff.position.y) + 0.5 }
end

local function stamp(force, id, at)
  return rig.call("stamp", { force = force, surface = game.surfaces.nauvis, design = id, position = at,
    charted_only = false, materials = false })
end

local function label(force, c, what)
  return "fix_cliffs " .. (force == FORCE and "cleared " or "blocked ") .. c.key .. ": " .. what
end

local function try_case(surface, force, o, i, c)
  local cliff, tile = cliff_near(surface, o.x - 90 + i * 30, o.y)
  local at = { x = tile.x + c.shift, y = tile.y }
  local id, reason, where = stamp(force, design(force, c.key), at)
  if force ~= FORCE and c.under then
    check.same(label(force, c, "refused at the cliff"), { id, reason, where }, { nil, "cliff", cliff.position })
  else
    check.truthy(label(force, c, "stamped"), id, reason)
  end
  local marked = cliff.valid and cliff.to_be_deconstructed()
  check.eq(label(force, c, "cliff marked for removal"), marked, force == FORCE and c.under)
end

-- A plan of one chest over a cliff: closed "cliff", or planned.
local function plan_over_cliff(surface, force, o)
  local cliff, tile = cliff_near(surface, o.x + 30, o.y + 20)
  return { cliff = cliff, force = force, params = { force = force, surface = surface, design = design(force, "one"),
    position = tile, dry_run = true, max_instances = 1, charted_only = false } }
end

-- Superforced over a cliff, a neutral chest nobody may remove and a tree:
-- the stamp comes out short.
local function short_over_cliff(surface, o)
  local cliff, tile = cliff_near(surface, o.x + 60, o.y + 20)
  surface.create_entity { name = "iron-chest", position = { tile.x + 3, tile.y }, force = "neutral" }
  local tree = surface.create_entity { name = "tree-01", position = { tile.x + 6, tile.y } }
  return { cliff = cliff, tree = tree, params = { force = FORCE, surface = surface, design = design(FORCE, "trio"),
    position = tile, superforce = true, max_instances = 1, materials = false, charted_only = false } }
end

function case.setup(surface)
  local s = { designs = {}, plans = {} }
  storage.fix_cliffs = s
  rig.own_force(FORCE)
  game.forces[FORCE].cliff_deconstruction_enabled = true
  for _, region in ipairs({ OFF, ON }) do
    local o = rig.region(region)
    rig.floor(surface, rig.box(o, -120, -40, 120, 40))
    local force = region == ON and FORCE or rig.FORCE
    for i, c in ipairs(CASES) do try_case(surface, force, o, i, c) end
    s.plans[force] = plan_over_cliff(surface, force, o)
  end
  s.rollback = short_over_cliff(surface, rig.region(ON))
end

function case.start()
  local s = storage.fix_cliffs
  for _, p in pairs(s.plans) do p.id = rig.call("start_project", p.params) end
  s.rollback.id = rig.call("start_project", s.rollback.params)
  check.truthy("fix_cliffs projects start", s.plans[rig.FORCE].id and s.plans[FORCE].id and s.rollback.id)
end

local function settled()
  local s = storage.fix_cliffs
  local off = rig.call("get_project", s.plans[rig.FORCE].id) or {}
  check.same("fix_cliffs blocked plan: closed at the cliff", { off.count, off.closed and off.closed.cliff }, { 0, 1 })
  local on = rig.call("get_project", s.plans[FORCE].id) or {}
  check.eq("fix_cliffs cleared plan: planned over the cliff", on.count, 1)
  check.eq("fix_cliffs cleared plan: marks nothing", s.plans[FORCE].cliff.to_be_deconstructed(), false)
  local r = s.rollback
  local rolled = rig.call("get_project", r.id) or {}
  local short = rolled.closed and rolled.closed["stamp-short"]
  check.same("fix_cliffs rollback: the short stamp is rolled back", { rolled.count, short }, { 0, 1 })
  check.eq("fix_cliffs rollback: the cliff is left unmarked", r.cliff.valid and r.cliff.to_be_deconstructed(), false)
  check.eq("fix_cliffs rollback: the tree is left unmarked", r.tree.valid and r.tree.to_be_deconstructed(), false)
end

case.checks = { [300] = settled }

return case
