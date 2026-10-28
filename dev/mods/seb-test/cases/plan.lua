-- plan.lua: dry runs, and superforce.
--   plan:       a dry run lays its whole plan out as outlines, with the same
--               checks as real growth (water stops it), and places no ghost
--   build:      building the finished plan starts a real project that grows
--               the same copies
--   preview:    a plan can paste its first copies as look-only ghosts of the
--               neutral force: robots never build them, and they go when the
--               plan is built or stopped
--   superforce: a building of the force in a copy's way is marked for
--               removal instead of closing the spot, in a plan too; a
--               superforced stamp that is rolled back (someone else's
--               building in the way) takes its removal orders back
--   room:       preview ghosts leave trees alone, and give way to a real copy

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "plan" }

local REGION = 40
local D = defines.direction
local CELL = { rig.panel(1.5, 1.5) }
local PAIR = { rig.panel(1.5, 1.5), rig.panel(4.5, 1.5) }

local function chest(surface, x, y)
  return surface.create_entity { name = "iron-chest", position = rig.offset(rig.region(REGION), x, y), force = rig.FORCE }
end

function case.setup(surface)
  local o = rig.site(surface, REGION)
  rig.water(surface, rig.box(o, 6, 0, 12, 12))
  storage.plan = { cell = rig.design(CELL, "Plan cell"), pair = rig.design(PAIR, "Plan pair") }
  local p = storage.plan
  p.forced_chest, p.plain_chest, p.planned_chest = chest(surface, 1.5, 41.5), chest(surface, 10.5, 41.5), chest(surface, 20.5, 41.5)
  -- Superforce over our chest and a chest nobody of ours may remove: the
  -- stamp comes out short and is rolled back.
  p.rolled_chest = chest(surface, 1.5, 51.5)
  surface.create_entity { name = "iron-chest", position = rig.offset(o, 4.5, 51.5), force = "neutral" }
  p.tree = surface.create_entity { name = "tree-01", position = rig.offset(o, 14.5, 51.5) }
end

local function start(extra)
  local params = { force = rig.FORCE, surface = game.surfaces.nauvis, design = extra.design or storage.plan.cell, charted_only = false }
  for k, v in pairs(extra) do params[k] = v end
  local id, reason = rig.call("start_project", params)
  check.truthy("plan project starts", id, reason)
  return id
end

local function neutral_ghosts(surface, box)
  return surface.count_entities_filtered {
    area = { { box.left, box.top }, { box.right, box.bottom } }, type = "entity-ghost", force = "neutral",
  }
end

function case.start()
  local p = storage.plan
  local id, reason = rig.call("start_project", {
    force = rig.FORCE, surface = game.surfaces.nauvis, design = p.cell, charted_only = false, dry_run = true,
    area = rig.box(rig.region(REGION), 0, 0, 12, 9), directions = { D.east, D.south },
  })
  check.truthy("plan dry run starts", id, reason)
  p.dry = id
  local o = rig.region(REGION)
  p.preview = start { dry_run = true, preview_ghosts = 2, area = rig.box(o, 0, 20, 12, 23), directions = { D.east } }
  p.dropped = start { dry_run = true, preview_ghosts = 3, area = rig.box(o, 0, 30, 12, 33), directions = { D.east } }
  p.forced = start { superforce = true, max_instances = 1, area = rig.box(o, 0, 40, 3, 43) }
  p.plain = start { max_instances = 1, area = rig.box(o, 9, 40, 12, 43) }
  p.planned_forced = start { dry_run = true, superforce = true, max_instances = 1, area = rig.box(o, 19, 40, 22, 43) }
  p.rolled = start { design = p.pair, superforce = true, max_instances = 1, area = rig.box(o, 0, 50, 6, 53) }
  p.treed = start { design = p.pair, dry_run = true, preview_ghosts = 1, max_instances = 1, area = rig.box(o, 10, 50, 16, 53) }
  p.roomy = start { design = p.pair, dry_run = true, preview_ghosts = 1, max_instances = 1, area = rig.box(o, 30, 50, 36, 53) }
end

local function previewed(surface)
  local p = storage.plan
  local o = rig.region(REGION)
  local preview = rig.call("get_project", p.preview)
  check.eq("plan preview lays out four copies", preview and preview.count, 4)
  check.eq("plan preview pastes its first two as neutral ghosts", neutral_ghosts(surface, rig.box(o, -1, 19, 13, 24)), 2)
  check.eq("plan preview pastes no ghost of the force", surface.count_entities_filtered {
    area = { { o.x - 1, o.y + 19 }, { o.x + 13, o.y + 24 } }, type = "entity-ghost", force = rig.FORCE }, 0)
  rig.call("stop_project", p.dropped)
  check.eq("plan preview ghosts go when the plan stops", neutral_ghosts(surface, rig.box(o, -1, 29, 13, 34)), 0)
  check.eq("plan superforce stamps over a building", rig.call("get_project", p.forced).count, 1)
  check.truthy("plan superforce marks the building for removal", p.forced_chest.valid and p.forced_chest.to_be_deconstructed()
    or not p.forced_chest.valid)
  local plain = rig.call("get_project", p.plain)
  check.eq("plan without superforce skips the building", plain and plain.count, 0)
  check.eq("plan without superforce leaves the building", p.plain_chest.valid and p.plain_chest.to_be_deconstructed(), false)
  check.eq("plan superforce counts in a plan", rig.call("get_project", p.planned_forced).count, 1)
  check.eq("plan superforce plan leaves the building", p.planned_chest.valid and p.planned_chest.to_be_deconstructed(), false)
  local rolled = rig.call("get_project", p.rolled)
  check.eq("plan superforce stamp rolled back", rolled and rolled.count, 0)
  check.eq("plan rolled-back superforce takes its order back", p.rolled_chest.valid and p.rolled_chest.to_be_deconstructed(), false)
  check.eq("plan preview leaves out the part a tree stands on", neutral_ghosts(surface, rig.box(o, 9, 49, 17, 54)), 1)
  check.eq("plan preview leaves the tree alone", p.tree.valid and p.tree.to_be_deconstructed(), false)
  -- A real copy over a plan's preview: the preview gives way.
  check.eq("plan preview to give way is there", neutral_ghosts(surface, rig.box(o, 29, 49, 37, 54)), 2)
  p.over = start { design = p.pair, max_instances = 1, area = rig.box(o, 30, 50, 36, 53) }
end

local function made_room(surface)
  local p = storage.plan
  local o = rig.region(REGION)
  check.eq("plan real copy stamped over a preview", rig.call("get_project", p.over).count, 1)
  check.eq("plan preview gave way to the real copy", neutral_ghosts(surface, rig.box(o, 29, 49, 37, 54)), 0)
end

-- Robots had all this time and built no preview ghost; building the plan
-- takes them away and grows the copies for real.
local function preview_built(surface)
  local p = storage.plan
  local o = rig.region(REGION)
  check.eq("plan preview ghosts are never built", neutral_ghosts(surface, rig.box(o, -1, 19, 13, 24)), 2)
  check.eq("plan preview built nothing real", rig.count(surface, rig.box(o, -1, 19, 13, 24), "solar-panel"), 0)
  p.preview_real = rig.call("build_project", p.preview)
  check.truthy("plan preview builds into a project", p.preview_real)
  check.eq("plan preview ghosts go when the plan is built", neutral_ghosts(surface, rig.box(o, -1, 19, 13, 24)), 0)
end

local function preview_grown(surface)
  local real = rig.call("get_project", storage.plan.preview_real)
  check.eq("plan preview grown for real", real and real.count, 4)
  check.eq("plan preview real panels", rig.count(surface, rig.box(rig.region(REGION), -1, 19, 13, 24), "solar-panel"), 4)
end

local function planned(surface)
  local p = storage.plan
  local o = rig.region(REGION)
  local dry = rig.call("get_project", p.dry)
  check.eq("plan laid out", dry and dry.status.level, "planned")
  -- Columns 0-3 and 3-6 fit; water from x = 6 stops the third.
  check.eq("plan counts the copies that fit", dry and dry.count, 6)
  check.eq("plan places no ghost", rig.ghosts(surface, rig.box(o, -1, -1, 13, 10)), 0)
  local drawn = rig.drawn(surface, rig.box(o, -1, -1, 13, 10))
  check.truthy("plan drawn as outlines", (drawn.rectangle or 0) >= 6, check.show(drawn))
  p.real = rig.call("build_project", p.dry)
  check.truthy("plan builds into a project", p.real)
  local gone = rig.call("get_project", p.dry)
  check.eq("plan stops once built", gone and gone.state, "stopped")
end

local function built(surface)
  local real = rig.call("get_project", storage.plan.real)
  check.eq("plan grown for real", real and real.count, 6)
  check.eq("plan real project finishes", real and real.status.level, "finished")
  check.eq("plan built panels", rig.count(surface, rig.box(rig.region(REGION), -1, -1, 13, 10), "solar-panel"), 6)
end

case.checks = {
  [300] = planned, [360] = previewed, [420] = made_room, [2400] = preview_built, [3000] = built, [5400] = preview_grown,
}

return case
