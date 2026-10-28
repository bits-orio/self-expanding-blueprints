-- Q8 Robots and markers: marker ghosts left inside a powered roboport network. Do robots try to build
-- them, and what happens when the marker item is put into storage by script? Centred on (200, 200),
-- far from every other band. Phase 1 (to tick 600): no marker items anywhere. Phase 2: insert them.
local lib = require("lib")
local q = {id = "Q8"}

local PHASE2_TICK = 660
local CONTROL = "wooden-chest"

local function ghost_at(surface, pos, name)
  return surface.find_entities_filtered{area = lib.tile_area(pos), ghost_name = name}[1]
end

function q.run(ctx)
  local s = ctx.surface
  local f = "player"
  local eei = s.create_entity{name = "electric-energy-interface", position = {196, 200}, force = f}
  eei.power_production = 1e9
  eei.electric_buffer_size = 1e10
  s.create_entity{name = "medium-electric-pole", position = {198.5, 200.5}, force = f}
  local port = s.create_entity{name = "roboport", position = {201, 200}, force = f}
  local robots = port.insert{name = "construction-robot", count = 20}
  local chest = s.create_entity{name = "storage-chest", position = {205.5, 200.5}, force = f}
  chest.insert{name = CONTROL, count = 10}

  local sites = {
    {name = lib.SOCKET, pos = {x = 210.5, y = 210.5}},
    {name = lib.TAG, pos = {x = 212.5, y = 210.5}},
    {name = lib.NOWIRE, pos = {x = 214.5, y = 210.5}},
    {name = CONTROL, pos = {x = 216.5, y = 210.5}},
  }
  for _, site in ipairs(sites) do
    local g = s.create_entity{name = "entity-ghost", inner_name = site.name, position = site.pos, direction = lib.E, force = f}
    site.ghost_unit = g and g.ghost_unit_number
    local items = g and g.ghost_prototype.items_to_place_this
    lib.log("Q8 ghost placed name=" .. site.name, "created=" .. tostring(g ~= nil), "items_to_place_this=" .. lib.ser(items))
  end
  storage.q8 = {port = port, chest = chest, sites = sites, phase = 1}
  lib.log("Q8 setup robots_inserted=" .. robots)
end

local ORDER_NAMES = {}
for k, v in pairs(defines.robot_order_type) do ORDER_NAMES[v] = k end

-- An item name that may come back as a string or as a prototype object.
local function item_name(x)
  if x == nil then return nil end
  if type(x) == "string" then return x end
  return x.name
end

-- What each deployed construction robot is doing: position and its order queue.
local function robot_orders(net)
  local out = {}
  for i, r in ipairs(net.construction_robots) do
    local orders = {}
    for _, o in ipairs(r.robot_order_queue or {}) do
      local t = o.target
      local tname = t and t.valid and (t.name == "entity-ghost" and ("ghost/" .. t.ghost_name) or t.name) or "-"
      local item = (o.item_to_place and item_name(o.item_to_place.name)) or (o.target_item and item_name(o.target_item.name)) or "-"
      orders[#orders + 1] = (ORDER_NAMES[o.type] or tostring(o.type)) .. ":" .. tname .. ":" .. item
    end
    local inv = r.get_inventory(defines.inventory.robot_cargo)
    local cargo = inv and not inv.is_empty() and lib.ser(inv.get_contents()) or "empty"
    out[#out + 1] = string.format("r%d@%.0f,%.0f cargo=%s orders=[%s]", i, r.position.x, r.position.y, cargo, table.concat(orders, ";"))
  end
  return table.concat(out, " | ")
end

local function status(tick)
  local st = storage.q8
  local s = game.surfaces.nauvis
  local net = st.port.valid and st.port.logistic_network
  local parts = {"tick=" .. tick, "phase=" .. st.phase}
  if net then
    parts[#parts + 1] = string.format("robots all=%d available=%d deployed=%d", net.all_construction_robots,
      net.available_construction_robots, #net.construction_robots)
  else
    parts[#parts + 1] = "no_network"
  end
  for _, site in ipairs(st.sites) do
    local ghost = ghost_at(s, site.pos, site.name) ~= nil
    local real = s.count_entities_filtered{area = lib.tile_area(site.pos), name = site.name}
    parts[#parts + 1] = string.format("%s:ghost=%s,real=%d", site.name, tostring(ghost), real)
  end
  local energy = st.port.valid and st.port.energy or -1
  parts[#parts + 1] = string.format("port_energy=%.0f", energy)
  lib.log("Q8 status", table.concat(parts, " "))
  if net and #net.construction_robots > 0 then lib.log("Q8 robots tick=" .. tick, robot_orders(net)) end
end

local function phase2()
  local st = storage.q8
  st.phase = 2
  local out = {}
  for _, name in ipairs({lib.SOCKET, lib.TAG, lib.NOWIRE}) do
    local ok, n = lib.try(function() return st.chest.insert{name = name, count = 5} end)
    out[#out + 1] = name .. "=" .. (ok and tostring(n) or ("ERR:" .. n))
  end
  local net = st.port.logistic_network
  local in_net = {}
  for _, name in ipairs({lib.SOCKET, lib.TAG, lib.NOWIRE}) do
    in_net[#in_net + 1] = name .. "=" .. tostring(net and net.get_item_count(name))
  end
  lib.log("Q8 phase2 chest.insert " .. table.concat(out, " "), "network_count " .. table.concat(in_net, " "))
end

function q.on_tick(e)
  local st = storage.q8
  if not st then return end
  if e.tick == PHASE2_TICK then phase2() end
  if e.tick % 120 == 0 or e.tick == PHASE2_TICK then status(e.tick) end
end

return q
