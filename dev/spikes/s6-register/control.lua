-- S6: what registering a design costs (calibration, picture), first and later.
local function blueprint(n, label)
  local inventory = game.create_inventory(1)
  local stack = inventory[1]
  stack.set_stack { name = "blueprint" }
  local entities = {}
  for i = 1, n do
    entities[i] = { entity_number = i, name = "solar-panel", position = { x = 1.5 + 3 * ((i - 1) % 4), y = 1.5 + 3 * math.floor((i - 1) / 4) } }
  end
  stack.set_blueprint_entities(entities)
  stack.label = label
  local text = stack.export_stack()
  inventory.destroy()
  return text
end

local function timed(what, fn)
  local profiler = helpers.create_profiler()
  fn()
  profiler.stop()
  log({ "", "SEB_SPIKE ", what, ": ", profiler })
end

script.on_init(function()
  for i, n in ipairs({ 1, 1, 4, 16, 1, 1 }) do
    timed("register #" .. i .. " (" .. n .. " panels)", function()
      remote.call("self-expanding-blueprints", "register_design", "player", blueprint(n, "D" .. i))
    end)
  end
  timed("update D2 (same cell)", function()
    remote.call("self-expanding-blueprints", "register_design", "player", blueprint(2, "D2"))
  end)
  local gallery = game.get_surface("seb-gallery")
  local calibration = game.get_surface("seb-calibration")
  local function count(s) local n = 0; for _ in s.get_chunks() do n = n + 1 end; return n end
  log("SEB_SPIKE chunks: gallery " .. (gallery and count(gallery) or -1) .. ", calibration " .. (calibration and count(calibration) or -1))
end)

-- Capture's steps on a concrete floor: create_blueprint, then registering it.
script.on_nth_tick(30, function(event)
  if event.tick ~= 30 then return end
  local surface = game.surfaces.nauvis
  for _, side in ipairs({ 32, 64, 128 }) do
    local x0 = side * 3
    local tiles = {}
    for x = 0, side - 1 do
      for y = 0, side - 1 do tiles[#tiles + 1] = { name = "concrete", position = { x0 + x, y } } end
    end
    surface.set_tiles(tiles)
    surface.create_entity { name = "small-lamp", position = { x0 + 2.5, 2.5 }, force = "player" }
    local inventory = game.create_inventory(1)
    local stack = inventory[1]
    stack.set_stack { name = "blueprint" }
    timed("create_blueprint " .. side, function()
      stack.create_blueprint { surface = surface, force = "player", area = { { x0, 0 }, { x0 + side, side } },
        always_include_tiles = true, include_modules = true }
    end)
    local text
    timed("export " .. side, function() text = stack.export_stack() end)
    timed("register " .. side, function()
      remote.call("self-expanding-blueprints", "register_design", "player", text)
    end)
    inventory.destroy()
  end
end)
