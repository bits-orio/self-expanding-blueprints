-- Seed only: a challenge for Self-Expanding Blueprints (DESIGN.md section 8).
-- Players have no character and so no hands: everything must be grown from
-- designs by robots. A powered roboport, its robots and a chest of
-- materials stand at the start, with one design registered for the
-- player force. The goal is a field of solar panels standing.

local GOAL = 400
local REMOTE = "self-expanding-blueprints"

local SEED = {
  { entity_number = 1, name = "solar-panel", position = { x = 1.5, y = 1.5 } },
  { entity_number = 2, name = "solar-panel", position = { x = 4.5, y = 1.5 } },
  { entity_number = 3, name = "solar-panel", position = { x = 1.5, y = 4.5 } },
  { entity_number = 4, name = "solar-panel", position = { x = 4.5, y = 4.5 } },
  { entity_number = 5, name = "medium-electric-pole", position = { x = 6.5, y = 3.5 } },
}

local STOCK = {
  { "solar-panel", 200 }, { "medium-electric-pole", 60 }, { "construction-robot", 50 }, { "roboport", 4 },
  { "storage-chest", 4 }, { "accumulator", 20 },
}

local function blueprint_string(entities, label)
  local inventory = game.create_inventory(1)
  local stack = inventory[1]
  stack.set_stack { name = "blueprint" }
  stack.set_blueprint_entities(entities)
  stack.label = label
  local text = stack.export_stack()
  inventory.destroy()
  return text
end

-- The seed: power, a roboport with robots, and a chest of materials.
local function plant(surface, force)
  local power = surface.create_entity { name = "electric-energy-interface", position = { -6, -6 }, force = force }
  power.power_production, power.electric_buffer_size = 2e7, 1e8
  power.minable_flag = false
  surface.create_entity { name = "medium-electric-pole", position = { -6, -3 }, force = force }
  local port = surface.create_entity { name = "roboport", position = { -2, -2 }, force = force }
  port.insert { name = "construction-robot", count = 30 }
  local chest = surface.create_entity { name = "storage-chest", position = { 2, -5 }, force = force }
  for _, s in ipairs(STOCK) do chest.insert { name = s[1], count = s[2] } end
end

script.on_init(function()
  local surface, force = game.surfaces.nauvis, game.forces.player
  surface.request_to_generate_chunks({ 0, 0 }, 3)
  surface.force_generate_chunk_requests()
  for _, e in pairs(surface.find_entities_filtered { area = { { -16, -16 }, { 16, 16 } } }) do
    if e.type ~= "character" and e.type ~= "resource" then e.destroy() end
  end
  plant(surface, force)
  force.chart(surface, { { -128, -128 }, { 128, 128 } })
end)

-- The seed design is registered a second in, once every mod has set up.
script.on_nth_tick(60, function()
  if storage.seeded then return end
  storage.seeded = true
  if remote.interfaces[REMOTE] then
    remote.call(REMOTE, "register_design", game.forces.player, blueprint_string(SEED, "Seed solar"))
  end
end)

-- No hands: a player's character goes, and the player watches as a god.
script.on_event(defines.events.on_player_created, function(event)
  local player = game.get_player(event.player_index)
  if not player then return end
  local character = player.character
  player.set_controller { type = defines.controllers.god }
  if character and character.valid then character.destroy() end
  player.print({ "seed-only.welcome" })
end)

local function count_panels()
  return game.surfaces.nauvis.count_entities_filtered { name = "solar-panel", force = "player" }
end

script.on_event(defines.events.on_robot_built_entity, function(event)
  if storage.won or event.entity.name ~= "solar-panel" then return end
  local n = count_panels()
  if n % 50 == 0 then game.print({ "seed-only.goal", n, GOAL }) end
  if n >= GOAL then
    storage.won = true
    game.print({ "seed-only.won", n })
    game.set_game_state { game_finished = true, player_won = true, can_continue = true }
  end
end, { { filter = "name", name = "solar-panel" } })
