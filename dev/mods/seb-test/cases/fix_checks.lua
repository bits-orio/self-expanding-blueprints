-- fix_checks.lua: checks, stamps and recounts look under a copy's parts,
-- not its whole footprint (regions 100, 103, 104).
--   sparse: two lamps 400 tiles apart over 160,000 ore: a chest under one
--           refuses the copy at that lamp, and without it the copy is
--           stamped (both timed, as INFO lines); its recount sees its two
--           ghosts built one by one
--   kept:   a lamp with Keep clear tiles beside it and 400 tiles away: a
--           chest on the far one refuses the copy at that tile; without it
--           the copy is stamped and a tree on the near one is cleared
--   room:   three plans pasting 20 look-only copies each; a real copy
--           stamped over one of them clears the previews under it, no others
--   shown:  a superforced plan over another team's chest plans the copy but
--           pastes no look-only ghost over that chest; its next copy shows

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "fix_checks" }

local SPARSE, KEPT, ROOM, SHOWN = 100, 103, 104, 105
local ROOM_FORCE = rig.FREE_FORCE
local ENTRY = { name = "seb-entry", position = { x = 0.5, y = 0.5 }, direction = defines.direction.north }
local function lamp(x, y) return { name = "small-lamp", position = { x = x, y = y } } end
local function keep(x, y) return { name = "seb-keep-clear", position = { x = x, y = y } } end

local function stamp(force, design, at)
  return rig.call("stamp", { force = force, surface = game.surfaces.nauvis, design = design, position = at,
    charted_only = false, materials = false })
end

-- A stamp with its time in an INFO line (never asserted on).
local function timed_stamp(what, force, design, at)
  local profiler = helpers.create_profiler()
  local id, reason, where = stamp(force, design, at)
  profiler.stop()
  log({ "", "SEB_TEST INFO fix_checks ", what, " (", tostring(id or reason), "): ", profiler })
  return id, reason, where
end

local function lamp_ghost(surface, at)
  return surface.find_entities_filtered { position = at, ghost_name = "small-lamp" }[1]
end

local function sparse_setup(surface, s)
  local o = rig.region(SPARSE)
  rig.floor(surface, rig.box(o, -200, -200, 200, 200))
  for x = -200, 199 do
    for y = -200, 199 do surface.create_entity { name = "iron-ore", position = { o.x + x + 0.5, o.y + y + 0.5 }, amount = 50 } end
  end
  local design = rig.design({ lamp(0.5, 0.5), ENTRY, lamp(399.5, 399.5) }, "Fix sparse")
  local near, far = rig.offset(o, -199.5, -199.5), rig.offset(o, 199.5, 199.5)
  local blocker = surface.create_entity { name = "iron-chest", position = far, force = rig.FORCE }
  local id, reason, where = timed_stamp("one check of 2 lamps 400 tiles apart over 160,000 ore", rig.FORCE, design, near)
  check.same("fix_checks sparse: a chest under the far lamp refuses the copy there", { id, reason, where },
    { nil, "building", far })
  blocker.destroy()
  id, reason = timed_stamp("one stamp of 2 lamps 400 tiles apart over 160,000 ore", rig.FORCE, design, near)
  check.truthy("fix_checks sparse: stamped over the ore", id, reason)
  local inst = id and rig.call("get_instance", id) or {}
  check.same("fix_checks sparse: its footprint is 400 tiles across", inst.footprint,
    { left = o.x - 200, top = o.y - 200, right = o.x + 200, bottom = o.y + 200 })
  local ghosts = { lamp_ghost(surface, near), lamp_ghost(surface, far) }
  check.truthy("fix_checks sparse: both lamps are ghosts", ghosts[1] and ghosts[2])
  if ghosts[1] then ghosts[1].revive { raise_revive = true } end
  s.sparse, s.far = id, far
end

local function kept_setup(surface, s)
  local o = rig.region(KEPT)
  rig.floor(surface, rig.box(o, -200, -200, 200, 200))
  local design = rig.design({ lamp(0.5, 0.5), ENTRY, keep(1.5, 0.5), keep(399.5, 399.5) }, "Fix kept")
  local at, far = rig.offset(o, -199.5, -199.5), rig.offset(o, 199.5, 199.5)
  local blocker = surface.create_entity { name = "iron-chest", position = far, force = rig.FORCE }
  local tree = surface.create_entity { name = "tree-01", position = { at.x + 1, at.y } }
  local id, reason, where = timed_stamp("one check of a lamp with a Keep clear tile 400 tiles away", rig.FORCE, design, at)
  check.same("fix_checks kept: a chest on the far kept tile refuses the copy there", { id, reason, where },
    { nil, "building", far })
  blocker.destroy()
  id, reason = stamp(rig.FORCE, design, at)
  check.truthy("fix_checks kept: stamped once the tile is clear", id, reason)
  check.truthy("fix_checks kept: the tree on the near kept tile is cleared", tree.valid and tree.to_be_deconstructed())
end

-- The plans' strips: each 60 tiles of 3-wide panels, 20 copies.
local function strip(k) return rig.box(rig.region(ROOM), 0, k * 10, 60, k * 10 + 3) end

local function neutral_ghosts(box)
  return game.surfaces.nauvis.count_entities_filtered {
    area = { { box.left, box.top }, { box.right, box.bottom } }, type = "entity-ghost", force = "neutral",
  }
end

function case.setup(surface)
  local s = {}
  storage.fix_checks = s
  sparse_setup(surface, s)
  kept_setup(surface, s)
  rig.own_force(ROOM_FORCE)
  rig.floor(surface, rig.box(rig.region(ROOM), -20, -20, 80, 40))
  s.cell = rig.call("register_design", ROOM_FORCE, rig.blueprint({ rig.panel(1.5, 1.5) }, { label = "Fix room cell" }))
  rig.floor(surface, rig.box(rig.region(SHOWN), -20, -20, 40, 40))
  s.foreign = surface.create_entity { name = "iron-chest", position = rig.offset(rig.region(SHOWN), 1.5, 1.5), force = rig.FORCE }
end

function case.start(surface)
  local s = storage.fix_checks
  s.plans = {}
  for k = 0, 2 do
    s.plans[#s.plans + 1] = rig.call("start_project", { force = ROOM_FORCE, surface = surface, design = s.cell,
      charted_only = false, dry_run = true, preview_ghosts = 20, area = strip(k), directions = { defines.direction.east } })
  end
  check.truthy("fix_checks room: three plans start", s.plans[3])
  s.shown = rig.call("start_project", { force = ROOM_FORCE, surface = surface, design = s.cell, charted_only = false,
    dry_run = true, superforce = true, preview_ghosts = 2, area = rig.box(rig.region(SHOWN), 0, 0, 6, 3),
    directions = { defines.direction.east } })
end

local function sparse_half(surface)
  local s = storage.fix_checks
  local inst = rig.call("get_instance", s.sparse) or {}
  check.same("fix_checks sparse recount: one lamp built, one ghost left", { inst.state, inst.ghosts_left }, { "building", 1 })
  local ghost = lamp_ghost(surface, s.far)
  if ghost then ghost.revive { raise_revive = true } end
end

local function sparse_done()
  local inst = rig.call("get_instance", storage.fix_checks.sparse) or {}
  check.same("fix_checks sparse recount: both built, complete", { inst.state, inst.ghosts_left }, { "complete", 0 })
end

-- Over the fifth copy of the middle plan, a real copy.
local function room_stamp()
  local s = storage.fix_checks
  check.same("fix_checks room: each plan shows 20 copies", { neutral_ghosts(strip(0)), neutral_ghosts(strip(1)),
    neutral_ghosts(strip(2)) }, { 20, 20, 20 })
  local fifth = rig.box(rig.region(ROOM), 12, 10, 15, 13)
  s.real = timed_stamp("a real copy over a plan's preview, three plans of 20 previews", ROOM_FORCE, s.cell,
    { x = fifth.left + 1.5, y = fifth.top + 1.5 })
  check.truthy("fix_checks room: the real copy is stamped over the preview", s.real)
  check.eq("fix_checks room: no preview left under it", neutral_ghosts(fifth), 0)
  check.same("fix_checks room: every other preview stays", { neutral_ghosts(strip(0)), neutral_ghosts(strip(1)),
    neutral_ghosts(strip(2)) }, { 20, 19, 20 })
end

local function shown()
  local s, o = storage.fix_checks, rig.region(SHOWN)
  check.eq("fix_checks shown: the superforced plan plans both copies", (rig.call("get_project", s.shown) or {}).count, 2)
  check.same("fix_checks shown: no look-only ghost over the other team's chest, the next copy shows",
    { neutral_ghosts(rig.box(o, 0, 0, 3, 3)), neutral_ghosts(rig.box(o, 3, 0, 6, 3)) }, { 0, 1 })
  check.eq("fix_checks shown: the chest is left alone", s.foreign.valid and not s.foreign.to_be_deconstructed(), true)
end

case.checks = { [240] = sparse_half, [420] = sparse_done, [600] = shown, [900] = room_stamp }

return case
