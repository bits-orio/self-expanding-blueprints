-- probes.lua: probes and pools.
--   probe:  a design whose probe asks for iron ore grows only over iron ore;
--           the first spot without closes with the reason "probe"
--   pool:   a labelled book registers as a pool; a socket naming it stamps
--           the first of its designs that fits (an ore-probed one over ore,
--           the next one elsewhere)

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "probes" }

local PROBE_REGION, POOL_REGION = 38, 39
local D = defines.direction

local function probe(x, y, signals)
  local filters = {}
  for i, s in ipairs(signals) do
    filters[i] = { index = i, type = s[1], name = s[2], quality = "normal", comparator = "=", count = 1 }
  end
  return {
    name = "seb-probe", position = { x = x, y = y },
    control_behavior = { sections = { sections = { { index = 1, filters = filters } } } },
  }
end

local CHEST = { name = "iron-chest", position = { x = 0.5, y = 0.5 } }
local IRON = { CHEST, probe(0.5, 0.5, { { "item", "iron-ore" } }) }
local LAMP = { { name = "small-lamp", position = { x = 0.5, y = 0.5 } } }

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

local function ore(surface, o, x, y)
  surface.create_entity { name = "iron-ore", position = { o.x + x + 0.5, o.y + y + 0.5 }, amount = 100 }
end

function case.setup(surface)
  local p = rig.site(surface, PROBE_REGION)
  for x = 0, 2 do ore(surface, p, x, 0) end
  local q = rig.site(surface, POOL_REGION)
  ore(surface, q, 1, 0)
  local ids, pool = rig.call("register_design", rig.FORCE, book("Pool test", { { "Pool iron", IRON }, { "Pool lamp", LAMP } }))
  check.eq("probes book registers two designs", ids and #ids, 2)
  check.eq("probes labelled book becomes a pool", pool, "Pool test")
  storage.probes = {
    iron = rig.design(IRON, "Probe iron"),
    seed = rig.design({ CHEST, rig.socket(1.5, 0.5, D.east, "Pool test") }, "Pool seed"),
    pool_ids = ids,
  }
end

local function start(design, region, dy, extra)
  local params = {
    force = rig.FORCE, surface = game.surfaces.nauvis, design = design, charted_only = false,
    area = rig.box(rig.region(region), 0, dy, 10, dy + 1), directions = { D.east },
  }
  for k, v in pairs(extra or {}) do params[k] = v end
  local id, reason = rig.call("start_project", params)
  check.truthy("probes project starts", id, reason)
  return id
end

function case.start()
  local s = storage.probes
  s.probe_project = start(s.iron, PROBE_REGION, 0, { max_instances = 6 })
  s.pool_ore = start(s.seed, POOL_REGION, 0)
  s.pool_bare = start(s.seed, POOL_REGION, 6)
end

local function design_of(project_id, n)
  local inst = rig.instances_of(project_id)[n]
  return inst and inst.design_id
end

local function verify()
  local s = storage.probes
  local p = rig.call("get_project", s.probe_project)
  check.eq("probes grows only over ore", p and p.count, 3)
  check.eq("probes closes where the probe fails", p and p.closed.probe, 1)
  check.eq("probes project finishes", p and p.status.level, "finished")
  check.eq("probes pool over ore stamps the probed design", design_of(s.pool_ore, 2), s.pool_ids and s.pool_ids[1])
  check.eq("probes pool elsewhere stamps the next design", design_of(s.pool_bare, 2), s.pool_ids and s.pool_ids[2])
  local pools = rig.call("list_pools", rig.FORCE)
  check.eq("probes list_pools names the pool", pools["Pool test"] and #pools["Pool test"], 2)
end

case.checks = { [1800] = verify }

return case
