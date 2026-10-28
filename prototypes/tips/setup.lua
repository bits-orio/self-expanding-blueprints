-- What the Tips and Tricks simulations share. A simulation is a string of Lua
-- that the engine runs as a console command inside a fresh simulation map
-- (`require` is not available there, so helpers are strings pasted in front
-- of a simulation's own code).

local setup = {}

-- The pieces every simulation is built from: WORLD prepares the lab,
-- TOOLS defines the helpers a scene is written with. A simulation's init is
-- `setup.WORLD .. setup.TOOLS .. <its scene>`; the scene then reads like a
-- script: build the world, register designs, and put what happens when in
-- `at(seconds, function() ... end)`. A scene never needs `update`: TOOLS
-- registers the one per-tick handler, which runs the timeline and the
-- animations of `pulse` and `drag`. Locals defined here: surface, force, MOD,
-- the four directions, GREEN and RED, camera, design, grow, stamp, network,
-- tiles, at, pulse, drag, loop. A tips simulation neither ends nor restarts
-- by itself (its `length` changes nothing: a counter kept running past it in
-- 2.1.23), so `setup.looping` builds one that plays again and again, each
-- pass in a lab surface of its own.
setup.WORLD = [=[
  local surface = game.surfaces[1]
  local force = game.forces.player
  -- Growth waits for chunks to exist, and a simulation generates none: the
  -- checkerboard's chunks are declared finished.
  surface.build_checkerboard({ { -64, -64 }, { 64, 64 } })
  for x = -2, 1 do
    for y = -2, 1 do surface.set_chunk_generated_status({ x, y }, defines.chunk_generated_status.entities) end
  end
  -- Nothing is charted in a simulation, so blueprint builders here may use
  -- any generated land (map setting seb-builders-charted-only, per force).
  remote.call("self-expanding-blueprints", "set_limits", force, { builders_charted_only = false })
  force.worker_robots_speed_modifier = 4
]=]

setup.TOOLS = [=[
  local MOD = "self-expanding-blueprints"
  local NORTH, EAST, SOUTH, WEST = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west
  -- The grow tool's selection colours: green to grow, red to remove.
  local GREEN = { r = 0.30, g = 0.75, b = 0.35 }
  local RED = { r = 0.85, g = 0.28, b = 0.25 }

  local function camera(x, y, zoom)
    game.simulation.camera_position = { x, y }
    game.simulation.camera_zoom = zoom
  end

  -- A design registered from a list of blueprint entities (positions in
  -- blueprint coordinates); returns its id.
  local function design(entities, label)
    local inventory = game.create_inventory(1)
    local stack = inventory[1]
    stack.set_stack { name = "blueprint" }
    for i, e in ipairs(entities) do e.entity_number = i end
    stack.set_blueprint_entities(entities)
    stack.label = label
    local id = remote.call(MOD, "register_design", force, stack.export_stack())
    inventory.destroy()
    return id
  end

  -- start_project / stamp on the lab, charted or not.
  local function grow(params)
    params.force, params.surface, params.charted_only = force, surface, false
    return remote.call(MOD, "start_project", params)
  end
  local function stamp(params)
    params.force, params.surface, params.charted_only = force, surface, false
    return remote.call(MOD, "stamp", params)
  end

  -- A powered roboport at (x, y) with its robots, and a storage chest at
  -- (x + 2.5, y - 2.5) holding `stock`, a list of { item, count }. The pole
  -- sits at (x - 2.5, y - 2.5) and the power source behind it.
  local function network(x, y, robots, stock)
    local power = surface.create_entity { name = "electric-energy-interface", position = { x - 4, y - 4 }, force = force }
    power.power_production, power.electric_buffer_size = 1e8, 1e9
    surface.create_entity { name = "medium-electric-pole", position = { x - 2.5, y - 2.5 }, force = force }
    local port = surface.create_entity { name = "roboport", position = { x, y }, force = force }
    port.insert { name = "construction-robot", count = robots }
    local chest = surface.create_entity { name = "storage-chest", position = { x + 2.5, y - 2.5 }, force = force }
    for _, entry in ipairs(stock) do chest.insert { name = entry[1], count = entry[2] } end
    return chest
  end

  -- Every tile of a box of whole tiles (left, top, right, bottom: right and
  -- bottom excluded) turned into `name`.
  local function tiles(name, left, top, right, bottom)
    local list = {}
    for x = left, right - 1 do
      for y = top, bottom - 1 do list[#list + 1] = { name = name, position = { x, y } } end
    end
    surface.set_tiles(list)
  end

  -- The timeline: at(seconds, action) runs `action` that many seconds after
  -- the simulation starts. Animations (pulse, drag) hang their per-tick step
  -- in `effects`; a step returns true when it is over.
  local tick, actions, effects = 0, {}, {}
  local every_tick   -- set by `loop`: sees each tick first, and may start the scene over
  local function at(seconds, action)
    actions[#actions + 1] = { tick = math.floor(seconds * 60 + 0.5), action = action }
  end
  script.on_nth_tick(1, function()
    tick = tick + 1
    if every_tick then every_tick(tick) end
    for _, entry in ipairs(actions) do
      if entry.tick == tick then entry.action() end
    end
    for i = #effects, 1, -1 do
      if effects[i](tick) then table.remove(effects, i) end
    end
  end)

  -- The engine's colours are premultiplied: a see-through one must have
  -- its channels scaled by its alpha, or it glows instead.
  local function tint(color, alpha)
    return { r = color.r * alpha, g = color.g * alpha, b = color.b * alpha, a = alpha }
  end

  -- A click: a ring that opens and fades around a dot.
  local function pulse(x, y, color)
    color = color or GREEN
    local born = tick
    local ring = rendering.draw_circle { surface = surface, target = { x, y }, radius = 0.3, width = 4, filled = false, color = tint(color, 1) }
    local dot = rendering.draw_circle { surface = surface, target = { x, y }, radius = 0.3, filled = true, color = tint(color, 1) }
    effects[#effects + 1] = function(now)
      local f = (now - born) / 45
      if f >= 1 then
        ring.destroy()
        dot.destroy()
        return true
      end
      ring.radius = 0.3 + 1.9 * f
      ring.color = tint(color, 1 - f)
      dot.color = tint(color, 1 - f)
      return false
    end
  end

  -- A drag with the grow tool: the selection box opens from its top-left
  -- corner to the bottom-right in `seconds` and stays until :destroy().
  -- Returns { destroy = function }.
  local function drag(box, color, seconds)
    local born, steps = tick, math.max(1, math.floor(seconds * 60 + 0.5))
    local corner = { box.left, box.top }
    local fill = rendering.draw_rectangle { surface = surface, left_top = corner, right_bottom = corner, filled = true,
      color = tint(color, 0.2), draw_on_ground = true }
    local edge = rendering.draw_rectangle { surface = surface, left_top = corner, right_bottom = corner, filled = false,
      width = 3, color = tint(color, 1), draw_on_ground = true }
    effects[#effects + 1] = function(now)
      if not fill.valid then return true end
      local f = math.min(1, (now - born) / steps)
      local far = { box.left + (box.right - box.left) * f, box.top + (box.bottom - box.top) * f }
      fill.right_bottom, edge.right_bottom = far, far
      return f >= 1
    end
    return { destroy = function() fill.destroy() edge.destroy() end }
  end

  -- loop(ticks, scene): plays `scene` (a function that builds the world and
  -- puts its timeline in `at`) in a lab of its own, and every `ticks` ticks
  -- again in a new one: the old lab is deleted, and the mod forgets its
  -- projects and copies with it. Everything a scene makes belongs on
  -- `surface`; the lab is empty lab tiles, always day.
  local labs_made = 0
  local function new_lab()
    labs_made = labs_made + 1
    local lab = game.create_surface("seb-tip-" .. labs_made, {
      default_enable_all_autoplace_controls = false, no_enemies_mode = true,
      autoplace_settings = {
        entity = { treat_missing_as_default = false, settings = {} },
        decorative = { treat_missing_as_default = false, settings = {} },
      },
    })
    lab.generate_with_lab_tiles = true
    lab.always_day = true
    lab.show_clouds = false
    lab.request_to_generate_chunks({ 0, 0 }, 2)
    lab.force_generate_chunk_requests()
    return lab
  end
  local function loop(ticks, scene)
    local function start()
      local old = surface
      surface = new_lab()
      game.simulation.camera_surface_index = surface.index
      tick, actions, effects = 0, {}, {}
      scene()
      if old.index ~= 1 then game.delete_surface(old) end
    end
    every_tick = function(now)
      if now >= ticks then start() end
    end
    start()
  end
]=]

-- A looping simulation: `scene` is Lua code that builds one pass (camera,
-- network, designs, tiles, its `at` timeline) and may use everything TOOLS
-- defines; `prelude` is code run once before the first pass (helpers). The
-- pass lasts `seconds`, then the world is thrown away and it plays again.
function setup.looping(seconds, scene, prelude)
  local ticks = math.floor(seconds * 60 + 0.5)
  return {
    mods = { "self-expanding-blueprints" }, checkboard = true, length = ticks,
    init = setup.WORLD .. setup.TOOLS .. (prelude or "")
      .. "local function scene()\n" .. scene .. "\nend\nloop(" .. ticks .. ", scene)\n",
  }
end

return setup
