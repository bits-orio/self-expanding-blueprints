-- S7: dangOreus kills every non-miner whose box covers ore, ghosts included.
-- Markers are points, so they must survive on ore; a chest must still die.
local ghost_check = require("ghosts")
local function report(what, value) log("SEB_SPIKE " .. what .. ": " .. tostring(value)) end

local function ore_spot(surface)
  for x = 160, 400, 4 do
    local ores = surface.find_entities_filtered { area = { { x, -2 }, { x + 4, 2 } }, type = "resource" }
    if #ores >= 12 then return { x = x + 1.5, y = 0.5 } end
  end
end

script.on_nth_tick(60, function(event)
  if event.tick ~= 120 then return end
  ghost_check(report)
  local surface, force = game.surfaces.nauvis, game.forces.player
  surface.request_to_generate_chunks({ 250, 0 }, 4)
  surface.force_generate_chunk_requests()
  local p = ore_spot(surface)
  report("ore spot", p and serpent.line(p))
  if not p then return end
  storage.kept = {}
  for i, name in ipairs({ "seb-sensor", "seb-socket", "seb-entry", "seb-probe", "seb-port" }) do
    local at = { p.x + i, p.y + 6 }
    storage.kept[#storage.kept + 1] = { name, surface.create_entity { name = name, position = at, force = force, raise_built = true } }
    storage.kept[#storage.kept + 1] = { name .. " ghost", surface.create_entity { name = "entity-ghost", inner_name = name, position = { at[1], at[2] + 2 }, force = force, raise_built = true } }
    local quiet = surface.create_entity { name = "entity-ghost", inner_name = name, position = { at[1], at[2] + 4 }, force = force }
    report(name .. " ghost on ore, no build event", quiet and quiet.valid)
    report(name .. " can_place ghost on ore", surface.can_place_entity { name = "entity-ghost", inner_name = name, position = { at[1], at[2] + 4.0 }, force = force, build_check_type = defines.build_check_type.manual_ghost })
  end
  storage.chest = surface.create_entity { name = "iron-chest", position = { p.x, p.y + 10 }, force = force, raise_built = true }
  storage.spot = p
  -- Growth on ore: a drill with a chest beside it (dangOreus kills the
  -- chest's ghost), and a drill with its sensor on the drill (allowed).
  local R = "self-expanding-blueprints"
  local function design(entities, label)
    local inventory = game.create_inventory(1)
    inventory[1].set_stack { name = "blueprint" }
    for i, e in ipairs(entities) do e.entity_number = i end
    inventory[1].set_blueprint_entities(entities)
    inventory[1].label = label
    local id = remote.call(R, "register_design", force, inventory[1].export_stack())
    inventory.destroy()
    return id
  end
  local drill = { name = "electric-mining-drill", position = { x = 1.5, y = 1.5 } }
  local with_chest = design({ drill, { name = "iron-chest", position = { x = 3.5, y = 1.5 } } }, "Drill and chest")
  local with_sensor = design({ { name = "electric-mining-drill", position = { x = 1.5, y = 1.5 } }, { name = "seb-sensor", position = { x = 2.5, y = 2.5 } } }, "Drill and sensor")
  local function grow(id, dy)
    return remote.call(R, "start_project", { force = force, surface = surface, design = id, charted_only = false,
      materials = false, max_instances = 1, area = { left = p.x - 1.5, top = p.y + dy, right = p.x + 6.5, bottom = p.y + dy + 3 } })
  end
  storage.chest_project, storage.sensor_project = grow(with_chest, 20), grow(with_sensor, 30)
end)

script.on_nth_tick(61, function(event)
  if event.tick ~= 122 or not storage.kept then return end
  for _, k in ipairs(storage.kept) do report(k[1] .. " on ore survives", k[2] and k[2].valid) end
  report("iron chest on ore dies (dangOreus active)", not (storage.chest and storage.chest.valid))
end)

script.on_nth_tick(180, function(event)
  if event.tick ~= 180 or not storage.chest_project then return end
  local R = "self-expanding-blueprints"
  local chest = remote.call(R, "get_project", storage.chest_project)
  report("drill and chest on ore: copies", chest.count)
  report("drill and chest on ore: why", serpent.line(chest.closed))
  local sensor = remote.call(R, "get_project", storage.sensor_project)
  report("drill and sensor on ore: copies", sensor.count)
  for id in pairs(remote.call(R, "get_project", storage.sensor_project).instance_ids or {}) do
    local inst = remote.call(R, "get_instance", id)
    report("drill and sensor: sensor watches", inst and serpent.line(inst.sensors))
  end
end)
