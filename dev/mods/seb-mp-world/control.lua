-- A lab world that registers a design and starts growing at tick 60, so a
-- client can join while the mod's queue handler is armed. dev/run-mp.sh
-- reads the SEB_MP lines from the server and the client logs.

local CELL = {
  { entity_number = 1, name = "solar-panel", position = { x = 1.5, y = 1.5 } },
  { entity_number = 2, name = "medium-electric-pole", position = { x = 3.5, y = 3.5 } },
}

local function floor(surface)
  surface.request_to_generate_chunks({ 0, 0 }, 4)
  surface.force_generate_chunk_requests()
  local tiles = {}
  for x = -100, 99 do
    for y = -100, 99 do tiles[#tiles + 1] = { name = "lab-dark-1", position = { x, y } } end
  end
  surface.set_tiles(tiles)
  for _, e in pairs(surface.find_entities_filtered { area = { { -100, -100 }, { 100, 100 } } }) do
    if e.type ~= "character" then e.destroy() end
  end
end

script.on_init(function()
  if remote.interfaces.freeplay then
    remote.call("freeplay", "set_skip_intro", true)
    remote.call("freeplay", "set_disable_crashsite", true)
  end
  local surface = game.surfaces.nauvis
  surface.always_day = true
  surface.show_clouds = false
  game.forces.enemy.kill_all_units()
  game.map_settings.enemy_expansion.enabled = false
  floor(surface)
  local force = game.forces.player
  local eei = surface.create_entity { name = "electric-energy-interface", position = { -12, -18 }, force = force }
  eei.power_production = 1e9
  eei.electric_buffer_size = 1e10
  surface.create_entity { name = "medium-electric-pole", position = { -12, -16 }, force = force }
  local port = surface.create_entity { name = "roboport", position = { -12, -12 }, force = force }
  port.insert { name = "construction-robot", count = 50 }
  local chest = surface.create_entity { name = "storage-chest", position = { -9, -16 }, force = force }
  chest.insert { name = "solar-panel", count = 400 }
  chest.insert { name = "medium-electric-pole", count = 400 }
end)

local function start_growing()
  local inventory = game.create_inventory(1)
  inventory[1].set_stack { name = "blueprint" }
  inventory[1].set_blueprint_entities(CELL)
  inventory[1].label = "MP cell"
  local text = inventory[1].export_stack()
  inventory.destroy()
  local design = remote.call("self-expanding-blueprints", "register_design", "player", text)
  storage.project = remote.call("self-expanding-blueprints", "start_project", {
    force = "player", surface = "nauvis", design = design, position = { x = 0, y = 0 },
    max_instances = 40, charted_only = false,
  })
  log("SEB_MP started project " .. tostring(storage.project))
end

script.on_nth_tick(60, function(event)
  if event.tick == 60 then start_growing() end
  if event.tick % 600 == 0 and storage.project then
    local p = remote.call("self-expanding-blueprints", "get_project", storage.project)
    log("SEB_MP tick=" .. event.tick .. " count=" .. p.count .. " building=" .. p.building .. " state=" .. p.state)
  end
end)
