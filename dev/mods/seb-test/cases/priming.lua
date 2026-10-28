-- priming.lua: designs primed with Blueprint Primer keep their item requests.
-- Priming is an insert plan on the blueprint entity (BlueprintEntity.items),
-- the same mechanism module requests use. A stamp must carry the exact plan
-- onto its ghosts, robots must deliver it, the instance must complete only
-- after delivery, and the materials gate must wait for priming items too.

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "priming" }

local REGION, STARVED_REGION = 10, 11
local INV = defines.inventory

local function plan(item, inventory, count)
  return { id = { name = item }, items = { in_inventory = { { inventory = inventory, stack = 0, count = count } } } }
end

local FURNACE = {
  name = "stone-furnace", position = { x = 1, y = 1 },
  items = { plan("coal", INV.fuel, 3), plan("iron-ore", INV.crafter_input, 7) },
}
local CHEST = { name = "iron-chest", position = { x = 3.5, y = 0.5 }, items = { plan("iron-plate", INV.chest, 5) } }

local STOCK = {
  { "stone-furnace", 10 }, { "iron-chest", 10 }, { "coal", 50 }, { "iron-ore", 50 }, { "iron-plate", 50 },
}

-- "item inventory[stack]=count" lines, sorted, from an insert plan.
local function plan_lines(insert_plan)
  local lines = {}
  for _, p in ipairs(insert_plan or {}) do
    for _, at in ipairs(p.items.in_inventory or {}) do
      lines[#lines + 1] = string.format("%s %d[%d]=%d", p.id.name, at.inventory, at.stack, at.count or 1)
    end
  end
  table.sort(lines)
  return lines
end

local function within(surface, id, filter)
  local inst = rig.call("get_instance", id)
  filter.area = { { inst.footprint.left, inst.footprint.top }, { inst.footprint.right, inst.footprint.bottom } }
  return surface.find_entities_filtered(filter)
end

function case.setup(surface)
  local o = rig.region(REGION)
  rig.floor(surface, rig.box(o, -60, -60, 60, 60))
  rig.network(surface, rig.offset(o, -20, -20), STOCK)
  local s = rig.region(STARVED_REGION)
  rig.floor(surface, rig.box(s, -60, -60, 60, 60))
  rig.network(surface, rig.offset(s, -20, -20), { { "stone-furnace", 10 }, { "iron-chest", 10 }, { "iron-ore", 50 }, { "iron-plate", 50 } })
  storage.priming = { design = rig.design({ FURNACE, CHEST }, "Primed cell") }
end

function case.start(surface)
  local p = storage.priming
  local o = rig.region(REGION)
  local id, reason = rig.call("stamp", { force = rig.FORCE, surface = surface, design = p.design, position = rig.offset(o, 10, 10) })
  check.truthy("priming stamp", id, reason)
  p.instance = id
  if not id then return end
  local furnace = within(surface, id, { type = "entity-ghost", ghost_name = "stone-furnace" })[1]
  local chest = within(surface, id, { type = "entity-ghost", ghost_name = "iron-chest" })[1]
  check.same("priming furnace ghost carries the exact plan", plan_lines(furnace and furnace.insert_plan),
    { "coal " .. INV.fuel .. "[0]=3", "iron-ore " .. INV.crafter_input .. "[0]=7" })
  check.same("priming chest ghost carries the exact plan", plan_lines(chest and chest.insert_plan),
    { "iron-plate " .. INV.chest .. "[0]=5" })
  -- A network with no coal: the materials gate must hold the primed design.
  p.starved = rig.call("start_project", {
    force = rig.FORCE, surface = surface, design = p.design, position = rig.offset(rig.region(STARVED_REGION), 10, 10),
    max_instances = 1, charted_only = false,
  })
end

-- Contents at the moment the instance completes: deliveries must be in.
function case.on_event(name, payload)
  local p = storage.priming
  if name ~= "on_instance_completed" or not p or payload.instance_id ~= p.instance then return end
  local surface = game.surfaces.nauvis
  local furnace = within(surface, p.instance, { name = "stone-furnace" })[1]
  local chest = within(surface, p.instance, { name = "iron-chest" })[1]
  p.at_completion = {
    -- Smelting starts on delivery: the ore in progress is in neither slot.
    ore_and_plates = furnace and (furnace.get_inventory(INV.crafter_input).get_item_count("iron-ore")
      + furnace.get_inventory(INV.crafter_output).get_item_count("iron-plate")
      + (furnace.is_crafting() and 1 or 0)) or -1,
    coal_received = furnace and (furnace.get_inventory(INV.fuel).get_item_count("coal") > 0
      or furnace.burner.currently_burning ~= nil) or false,
    chest_plates = chest and chest.get_inventory(INV.chest).get_item_count("iron-plate") or -1,
  }
end

local function verify()
  local p = storage.priming
  local inst = p.instance and rig.call("get_instance", p.instance)
  check.eq("priming instance complete", inst and inst.state, "complete")
  local got = p.at_completion or {}
  check.eq("priming all 7 ore delivered before completion", got.ore_and_plates, 7)
  check.eq("priming coal delivered before completion", got.coal_received, true)
  check.eq("priming chest holds exactly 5 plates at completion", got.chest_plates, 5)
  local starved = rig.call("get_project", p.starved)
  check.eq("priming starved network waits for the priming coal", starved and starved.gate, "missing-materials")
  check.eq("priming starved network stamps nothing", starved and starved.count, 0)
end

case.checks = { [3000] = verify }

return case
