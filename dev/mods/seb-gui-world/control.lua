-- A lab floor with a roboport network and stock around the origin. The
-- player starts next to it holding a solar-cell blueprint, ready to press
-- ALT + G and "Add blueprint in hand".

local CELL = {
  { entity_number = 1, name = "solar-panel", position = { x = 1.5, y = 1.5 } },
  { entity_number = 2, name = "solar-panel", position = { x = 4.5, y = 1.5 } },
  { entity_number = 3, name = "solar-panel", position = { x = 1.5, y = 4.5 } },
  { entity_number = 4, name = "solar-panel", position = { x = 4.5, y = 4.5 } },
  { entity_number = 5, name = "medium-electric-pole", position = { x = 6.5, y = 3.5 } },
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
  local water = {}
  for x = 30, 60 do
    for y = -20, 60 do water[#water + 1] = { name = "water", position = { x, y } } end
  end
  surface.set_tiles(water)
end

local function network(surface, force)
  local eei = surface.create_entity { name = "electric-energy-interface", position = { -12, -18 }, force = force }
  eei.power_production = 1e9
  eei.electric_buffer_size = 1e10
  surface.create_entity { name = "medium-electric-pole", position = { -12, -16 }, force = force }
  local port = surface.create_entity { name = "roboport", position = { -12, -12 }, force = force }
  port.insert { name = "construction-robot", count = 100 }
  local chest = surface.create_entity { name = "storage-chest", position = { -9, -16 }, force = force }
  chest.insert { name = "solar-panel", count = 400 }
  chest.insert { name = "medium-electric-pole", count = 100 }
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
  local force = game.forces.player
  force.worker_robots_speed_modifier = 4
  floor(surface)
  network(surface, force)
  force.chart(surface, { { -128, -128 }, { 128, 128 } })
end)

-- The player has no cursor yet when created (freeplay builds the character
-- afterwards), so the blueprint is handed over a second later. Dev world only.
local function give_blueprint(player)
  local stack = player.cursor_stack
  if not stack then return false end
  stack.set_stack { name = "blueprint" }
  stack.set_blueprint_entities(CELL)
  stack.label = "Solar cell"
  return true
end

script.on_nth_tick(60, function()
  storage.given = storage.given or {}
  for _, player in pairs(game.connected_players) do
    if not storage.given[player.index] then
      if player.position.y > -5 then player.teleport({ 0, -6 }) end
      storage.given[player.index] = give_blueprint(player)
    end
  end
end)
