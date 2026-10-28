-- Grass stages for recording the portal GIFs (dev/record-media.sh): each
-- scene has its own stage, cleared of trees and rocks, with a roboport
-- network and stock, some with a lake that stops growth. The designs the
-- scenes use are registered for the player's team. remote.call("seb-media",
-- "go", scene) puts the player on a stage. Dev world only.

local D = defines.direction

local SCENES = {
  grow = { x = 0, y = 0, lake = true },
  fill = { x = 0, y = 300 },
  turn = { x = 0, y = 600 },
  sockets = { x = 0, y = 900, lake = true },
  plan = { x = 300, y = 0 },
  -- Spares for retakes, so a failed take needs no new world.
  spare0 = { x = 300, y = 300 },
  spare1 = { x = 300, y = 600 },
  spare2 = { x = 300, y = 900 },
  spare3 = { x = 600, y = 0 },
  spare4 = { x = 600, y = 300 },
}
local HALF_W, HALF_H = 100, 70

-- The pole stands between the panels, so it reaches all four.
local SOLAR = {
  { name = "solar-panel", position = { x = 1.5, y = 1.5 } },
  { name = "solar-panel", position = { x = 5.5, y = 1.5 } },
  { name = "solar-panel", position = { x = 1.5, y = 4.5 } },
  { name = "solar-panel", position = { x = 5.5, y = 4.5 } },
  { name = "medium-electric-pole", position = { x = 3.5, y = 3.5 } },
}

-- A road piece that grows east from its socket and hangs a solar cell off
-- its north side.
local ROAD = {
  { name = "medium-electric-pole", position = { x = 0.5, y = 3.5 } },
  { name = "small-lamp", position = { x = 2.5, y = 3.5 } },
  { name = "seb-entry", position = { x = 0.5, y = 1.5 }, direction = D.east },
  { name = "seb-socket", position = { x = 8.5, y = 1.5 }, direction = D.east },
  { name = "seb-socket", position = { x = 4.5, y = -0.5 }, direction = D.north, player_description = "Solar cell" },
}

local function road_tiles()
  local tiles = {}
  for x = 0, 7 do
    for y = 0, 2 do tiles[#tiles + 1] = { name = "stone-path", position = { x = x, y = y } } end
  end
  return tiles
end

local STOCK = {
  { "solar-panel", 400 }, { "medium-electric-pole", 200 }, { "small-lamp", 100 }, { "stone-brick", 800 },
}

local function blueprint(entities, tiles, label)
  local inventory = game.create_inventory(1)
  local stack = inventory[1]
  stack.set_stack { name = "blueprint" }
  for i, e in ipairs(entities) do e.entity_number = i end
  stack.set_blueprint_entities(entities)
  if tiles then stack.set_blueprint_tiles(tiles) end
  stack.label = label
  local text = stack.export_stack()
  inventory.destroy()
  return text
end

local function lake(surface, c)
  local water = {}
  for x = 40, 80 do
    for y = -50, 50 do
      local dx, dy = (x - 62) / 22, y / 46
      if dx * dx + dy * dy <= 1 + 0.08 * math.sin(y / 5) then
        water[#water + 1] = { name = "water", position = { c.x + x, c.y + y } }
      end
    end
  end
  surface.set_tiles(water)
end

local function stage(surface, c)
  local area = { { c.x - HALF_W, c.y - HALF_H }, { c.x + HALF_W, c.y + HALF_H } }
  surface.request_to_generate_chunks(c, 5)
  surface.force_generate_chunk_requests()
  local tiles = {}
  for x = c.x - HALF_W, c.x + HALF_W - 1 do
    for y = c.y - HALF_H, c.y + HALF_H - 1 do tiles[#tiles + 1] = { name = "grass-1", position = { x, y } } end
  end
  surface.set_tiles(tiles)
  for _, e in pairs(surface.find_entities_filtered { area = area }) do
    if e.valid and e.type ~= "character" then e.destroy() end
  end
  surface.destroy_decoratives { area = area }
  if c.lake then lake(surface, c) end
end

local function roboport(surface, force, at)
  local port = surface.create_entity { name = "roboport", position = at, force = force }
  port.insert { name = "construction-robot", count = 60 }
  surface.create_entity { name = "medium-electric-pole", position = { at.x + 2.5, at.y + 0.5 }, force = force }
  local eei = surface.create_entity { name = "electric-energy-interface", position = { at.x + 4, at.y }, force = force }
  eei.power_production = 1e9
  eei.electric_buffer_size = 1e10
  local chest = surface.create_entity { name = "storage-chest", position = { at.x - 2.5, at.y + 0.5 }, force = force }
  for _, s in ipairs(STOCK) do chest.insert { name = s[1], count = s[2] } end
end

local function network(surface, force, c)
  for _, dx in ipairs { -20, 30 } do
    for _, dy in ipairs { -30, 30 } do roboport(surface, force, { x = c.x + dx, y = c.y + dy }) end
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
  game.map_settings.pollution.enabled = false
  local force = game.forces.player
  force.worker_robots_speed_modifier = 4
  for _, c in pairs(SCENES) do
    stage(surface, c)
    network(surface, force, c)
    force.chart(surface, { { c.x - HALF_W, c.y - HALF_H }, { c.x + HALF_W, c.y + HALF_H } })
  end
  force.research_all_technologies()
  local seb = "self-expanding-blueprints"
  remote.call(seb, "register_design", force.name, blueprint(SOLAR, nil, "Solar cell"))
  remote.call(seb, "register_design", force.name, blueprint(ROAD, road_tiles(), "Road"))
end)

remote.add_interface("seb-media", {
  -- Puts the player on a scene's stage, `dx` tiles right of its middle.
  go = function(scene, dx)
    local player, c = game.get_player(1), SCENES[scene]
    if not (player and c) then return false end
    player.teleport({ c.x + (dx or -10), c.y + 0.5 })
    return true
  end,
})
