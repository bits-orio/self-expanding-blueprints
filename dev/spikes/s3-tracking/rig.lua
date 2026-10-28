-- The test rig on nauvis: a flat lab-tile area, three powered roboports with
-- construction robots, and storage chests holding every item the designs use.
local lg = require("lg")
local R = {}

R.AREA = {x0 = -80, y0 = -64, x1 = 96, y1 = 64}

R.ITEMS = {
  {name = "iron-chest", count = 300},
  {name = "wooden-chest", count = 50},
  {name = "small-lamp", count = 20},
  {name = "assembling-machine-2", count = 10},
  {name = "speed-module", count = 20},
  {name = "constant-combinator", count = 10},
  {name = "stone-brick", count = 400},
  {name = "concrete", count = 100},
  {name = "landfill", count = 50},
}

local function create(surface, t)
  t.force = t.force or "player"
  local e = surface.create_entity(t)
  if not e then error("rig: could not create " .. t.name .. " at " .. lg.ser(t.position)) end
  return e
end
R.create = create

local function stock(chests, items)
  for _, it in pairs(items) do
    local left = it.count
    for _, c in pairs(chests) do
      if left <= 0 then break end
      left = left - c.insert{name = it.name, count = left}
    end
    if left > 0 then error("rig: no room for " .. it.name) end
  end
end

local function flatten(surface)
  local a = R.AREA
  local area = {{a.x0, a.y0}, {a.x1, a.y1}}
  surface.request_to_generate_chunks({0, 0}, 5)
  surface.force_generate_chunk_requests()
  for _, e in pairs(surface.find_entities_filtered{area = area}) do
    if e.valid and e.type ~= "character" then e.destroy() end
  end
  local tiles = {}
  for x = a.x0, a.x1 - 1 do
    for y = a.y0, a.y1 - 1 do
      tiles[#tiles + 1] = {name = "lab-dark-1", position = {x, y}}
    end
  end
  surface.set_tiles(tiles, true, true, true, false)
  surface.destroy_decoratives{area = area}
  game.forces.enemy.kill_all_units()
  for _, e in pairs(surface.find_entities_filtered{force = "enemy"}) do e.destroy() end
  game.map_settings.enemy_expansion.enabled = false
  game.map_settings.pollution.enabled = false
  surface.peaceful_mode = true
end

function R.build(surface)
  flatten(surface)
  local eei = create(surface, {name = "electric-energy-interface", position = {0, -4}})
  eei.power_production = 1e9
  eei.electric_buffer_size = 1e10
  local p1 = create(surface, {name = "medium-electric-pole", position = {-2.5, -2.5}})
  local p2 = create(surface, {name = "medium-electric-pole", position = {2.5, -2.5}})
  p1.get_wire_connector(defines.wire_connector_id.pole_copper, true)
    .connect_to(p2.get_wire_connector(defines.wire_connector_id.pole_copper, true), false)
  local robots = 0
  for _, x in pairs({-4, 0, 4}) do
    local rp = create(surface, {name = "roboport", position = {x, 0}})
    robots = robots + rp.get_inventory(defines.inventory.roboport_robot)
      .insert{name = "construction-robot", count = 100}
  end
  local chests = {}
  for i = 0, 5 do
    chests[#chests + 1] = create(surface, {name = "storage-chest", position = {-2.5 + i, 3.5}})
  end
  stock(chests, R.ITEMS)
  storage.rig = {chests = chests}
  lg.out("RIG ready robots=" .. robots .. " storage_chests=" .. #chests)
end

-- Item counts across the storage chests, for checking what robots took.
function R.stock_counts()
  local counts = {}
  for _, c in pairs(storage.rig.chests) do
    for _, it in pairs(c.get_inventory(defines.inventory.chest).get_contents()) do
      counts[it.name] = (counts[it.name] or 0) + it.count
    end
  end
  return counts
end

return R
