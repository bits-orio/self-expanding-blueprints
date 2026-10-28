-- tracking.lua: completion comes from tags and recounts on every build path.
--   revived ghosts complete an instance without robots;
--   ghosts removed unbuilt make it incomplete;
--   a tracked entity that dies leaves a ghost carrying the instance tag;
--   module requests must be delivered before an instance completes;
--   tile ghosts count, and retiring removes the instance's tiles too.

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "tracking" }

local SYNC_REGION, ROBOT_REGION = 2, 3
local CELL = {
  { name = "solar-panel", position = { x = 1.5, y = 1.5 } },
  { name = "medium-electric-pole", position = { x = 3.5, y = 0.5 } },
}

local function tagged_ghosts(surface, id)
  local inst = rig.call("get_instance", id)
  local found = {}
  for _, g in pairs(surface.find_entities_filtered {
    area = { { inst.footprint.left, inst.footprint.top }, { inst.footprint.right, inst.footprint.bottom } },
    type = "entity-ghost",
  }) do
    if g.tags and g.tags.seb_instance == id then found[#found + 1] = g end
  end
  return found
end

local function stamp(surface, design, at)
  local id, reason = rig.call("stamp", { force = rig.FORCE, surface = surface, design = design, position = at })
  check.truthy("tracking stamp at " .. at.x, id, reason)
  return id
end

local function sync_cases(surface, design)
  local o = rig.region(SYNC_REGION)
  local t = storage.tracking
  t.revived = stamp(surface, design, rig.offset(o, 0, 0))
  local ghosts = tagged_ghosts(surface, t.revived)
  check.eq("tracking stamp tags every ghost", #ghosts, 2)
  for _, g in ipairs(ghosts) do g.revive { raise_revive = true } end

  -- One part built, the other's ghost removed: incomplete. With every ghost
  -- removed nothing would be left, and the copy released (vanish.lua).
  t.removed = stamp(surface, design, rig.offset(o, 10, 0))
  local removed = tagged_ghosts(surface, t.removed)
  removed[1].revive { raise_revive = true }
  removed[2].destroy()

  t.partial = stamp(surface, design, rig.offset(o, 20, 0))
  local pair = tagged_ghosts(surface, t.partial)
  pair[1].revive { raise_revive = true }
  pair[2].destroy()

  t.dies = stamp(surface, design, rig.offset(o, 30, 0))
  for _, g in ipairs(tagged_ghosts(surface, t.dies)) do g.revive { raise_revive = true } end
end

local MODULES = {
  name = "assembling-machine-2", position = { x = 1.5, y = 1.5 },
  items = { {
    id = { name = "speed-module" },
    items = { in_inventory = {
      { inventory = defines.inventory.crafter_modules, stack = 0, count = 1 },
      { inventory = defines.inventory.crafter_modules, stack = 1, count = 1 },
    } },
  } },
}

local function paved_cell()
  local tiles = {}
  for x = 0, 3 do
    for y = 0, 3 do tiles[#tiles + 1] = { name = "stone-path", position = { x = x, y = y } } end
  end
  return tiles
end

function case.setup(surface)
  storage.tracking = {}
  local o = rig.region(SYNC_REGION)
  rig.floor(surface, rig.box(o, -10, -10, 60, 20))
  game.forces[rig.FORCE].create_ghost_on_entity_death = true
  sync_cases(surface, rig.design(CELL, "Tracking cell"))
  local r = rig.region(ROBOT_REGION)
  rig.floor(surface, rig.box(r, -60, -60, 60, 60))
  rig.network(surface, rig.offset(r, -20, -20), {
    { "speed-module", 10 }, { "assembling-machine-2", 5 }, { "solar-panel", 10 },
    { "medium-electric-pole", 10 }, { "stone-brick", 100 },
  })
  storage.tracking.modules_design = rig.design({ MODULES }, "Tracking modules")
  storage.tracking.paved_design = rig.design(CELL, "Tracking paved", { tiles = paved_cell() })
end

function case.start(surface)
  local r = rig.region(ROBOT_REGION)
  local t = storage.tracking
  t.modules = stamp(surface, t.modules_design, rig.offset(r, 10, 10))
  t.paved = stamp(surface, t.paved_design, rig.offset(r, 20, 10))
  -- Kill a built entity of a complete instance: its death ghost must carry the tag.
  local inst = rig.call("get_instance", t.dies)
  local pole = surface.find_entities_filtered {
    area = { { inst.footprint.left, inst.footprint.top }, { inst.footprint.right, inst.footprint.bottom } },
    name = "medium-electric-pole",
  }[1]
  check.truthy("tracking pole to kill exists", pole)
  if pole then pole.die() end
  local ghost = surface.find_entities_filtered {
    area = { { inst.footprint.left, inst.footprint.top }, { inst.footprint.right, inst.footprint.bottom } },
    ghost_name = "medium-electric-pole",
  }[1]
  check.truthy("tracking death ghost carries the tag", ghost and ghost.tags and ghost.tags.seb_instance == t.dies,
    check.show(ghost and ghost.tags))
end

local function module_count(surface, id)
  local inst = rig.call("get_instance", id)
  local machine = surface.find_entities_filtered {
    area = { { inst.footprint.left, inst.footprint.top }, { inst.footprint.right, inst.footprint.bottom } },
    name = "assembling-machine-2",
  }[1]
  return machine and machine.get_module_inventory().get_item_count("speed-module") or -1
end

function case.on_event(name, payload)
  local t = storage.tracking
  if name == "on_instance_completed" and t and payload.instance_id == t.modules then
    t.modules_at_completion = module_count(game.surfaces.nauvis, t.modules)
  end
end

local function state_of(id)
  local inst = rig.call("get_instance", id)
  return inst and inst.state
end

local function first_check(surface)
  local t = storage.tracking
  check.eq("tracking revived ghosts complete the instance", state_of(t.revived), "complete")
  check.eq("tracking removed ghosts make it incomplete", state_of(t.removed), "incomplete")
  check.eq("tracking half removed is incomplete", state_of(t.partial), "incomplete")
end

local function robot_check(surface)
  local t = storage.tracking
  check.eq("tracking modules instance complete", state_of(t.modules), "complete")
  check.eq("tracking modules were in place at completion", t.modules_at_completion, 2)
  check.eq("tracking paved instance complete", state_of(t.paved), "complete")
  local inst = rig.call("get_instance", t.paved)
  check.eq("tracking paved tiles built", surface.count_tiles_filtered {
    area = { { inst.footprint.left, inst.footprint.top }, { inst.footprint.right, inst.footprint.bottom } },
    name = "stone-path",
  }, 16)
  t.paved_footprint = rig.call("get_instance", t.paved).footprint
  local ok, reason = rig.call("remove_instance", t.paved)
  check.truthy("tracking paved retire accepted", ok, reason)
  check.eq("tracking died entity rebuilt", state_of(t.dies), "complete")
end

local function retired_check(surface)
  local t = storage.tracking
  local fp = t.paved_footprint
  check.eq("tracking paved retired, then forgotten", rig.call("get_instance", t.paved), nil)
  check.eq("tracking paved tiles removed", surface.count_tiles_filtered {
    area = { { fp.left, fp.top }, { fp.right, fp.bottom } },
    name = "stone-path",
  }, 0)
end

case.checks = { [300] = first_check, [2400] = robot_check, [4800] = retired_check }

return case
