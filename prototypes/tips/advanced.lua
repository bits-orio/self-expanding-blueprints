-- Tips and Tricks entries about planning, keeping designs up to date and the
-- circuit layer: plan only, fast fill, updates and research, the blueprint
-- builder, stamping a grid and ports. Each has one simulation that runs the
-- mod itself (prototypes/tips/setup.lua says how a scene is written): the
-- scene is what happens on screen, the prelude what it is written with.

local setup = require("prototypes.tips.setup")

local simulation = setup.looping

local function tip(name, order, indent, extra)
  local item = {
    type = "tips-and-tricks-item", name = name, category = "self-expanding-blueprints", order = order,
    indent = indent, starting_status = "unlocked", dependencies = { "seb-grow" },
  }
  for k, v in pairs(extra) do item[k] = v end
  if item.is_title then item.dependencies = nil end
  return item
end

-- A 7 x 6 field cell, the one the first entry grows: four solar panels and a
-- pole at its east edge.
local CELL = [=[
  local cell = design({
    { name = "solar-panel", position = { 1.5, 1.5 } }, { name = "solar-panel", position = { 4.5, 1.5 } },
    { name = "solar-panel", position = { 1.5, 4.5 } }, { name = "solar-panel", position = { 4.5, 4.5 } },
    { name = "medium-electric-pole", position = { 6.5, 2.5 } },
  }, "Solar cell")
]=]

-- One solar panel, 3 x 3.
local PANEL = [=[
  local panel = design({ { name = "solar-panel", position = { 1.5, 1.5 } } }, "Panel")
]=]

-- A caption in the world, written in the mod's own words when they exist
-- (`fallback` otherwise, so a missing line never shows as a key).
local CAPTION = [=[
  local function caption(x, y, key, fallback, ...)
    return rendering.draw_text { surface = surface, target = { x, y }, text = { "?", { key, ... }, fallback },
      color = { 1, 1, 1 }, scale = 2, scale_with_zoom = true, alignment = "center", vertical_alignment = "middle" }
  end
]=]

-- What the circuit scenes add to the shared tools: a blueprint builder with
-- the constant combinator that plays its program (five tiles west, wired to
-- its red input), a way to put a request on that program, the builder's
-- answer as a table, `every` (a step that runs every n ticks, hung in the
-- tools' per-tick `effects`) and two drawings, because signals on a wire
-- cannot be read in a simulation: the request as a column of icons with
-- their values above the program, and the builder's answers beside the
-- builder. Alt info stays on for the recipe icons of an assembler.
local CIRCUIT = [=[
  game.simulation.camera_alt_info = true

  -- A signal as a wire shows it: its icon, then its value. Sizes in tiles.
  local ICON, ROW, DIGITS = 1.0, 1.25, 2.2
  local function draw_signal(x, y, name, value, kind)
    return {
      rendering.draw_sprite { sprite = (kind == "item" and "item/" or "virtual-signal/") .. name, surface = surface,
        target = { x, y }, x_scale = ICON, y_scale = ICON },
      rendering.draw_text { surface = surface, target = { x + 0.7, y }, text = tostring(value), color = { 1, 1, 1 },
        scale = DIGITS, alignment = "left", vertical_alignment = "middle" },
    }
  end
  local function erase(objects)
    for _, object in ipairs(objects) do
      if object.valid then object.destroy() end
    end
  end

  local function builder_at(x, y)
    local builder = surface.create_entity { name = "seb-builder", position = { x, y }, force = force, raise_built = true }
    local program = surface.create_entity { name = "constant-combinator", position = { x - 5, y + 0.5 }, force = force }
    program.get_wire_connector(defines.wire_connector_id.circuit_red, true)
      .connect_to(builder.get_wire_connector(defines.wire_connector_id.combinator_input_red, true), false)
    return builder, program
  end

  -- A request is a list of { signal, count } (virtual signals; a third entry
  -- names another kind, "item" for an item signal). It replaces whatever the
  -- program held, and is drawn above the program, a row for each signal.
  local requests = {}
  local function send(program, request)
    local filters = {}
    for i, entry in ipairs(request) do
      filters[i] = { value = { type = entry[3] or "virtual", name = entry[1], quality = "normal", comparator = "=" }, min = entry[2] }
    end
    program.get_or_create_control_behavior().get_section(1).filters = filters
    erase(requests[program.unit_number] or {})
    local drawn, at = {}, program.position
    for i, entry in ipairs(request) do
      local y = at.y - 0.9 - (#request - i + 0.5) * ROW
      for _, object in ipairs(draw_signal(at.x - 0.6, y, entry[1], entry[2], entry[3])) do drawn[#drawn + 1] = object end
    end
    requests[program.unit_number] = drawn
  end

  -- What the builder shows on its output, as { ["virtual/seb-done"] = 1, ... }.
  local function answers(builder)
    local out = {}
    for _, s in ipairs(builder.get_signals(defines.wire_connector_id.combinator_output_red) or {}) do
      out[(s.signal.type or "item") .. "/" .. s.signal.name] = s.count
    end
    return out
  end

  local function every(ticks, action)
    effects[#effects + 1] = function(now)
      if now % ticks == 0 then action() end
      return false
    end
  end

  -- Request accepted, Request done and Request failed as icons with their
  -- request number, three slots side by side to the right of the builder,
  -- drawn while the builder shows them.
  local function readout(builder)
    local shown = {}
    local x, y = builder.position.x + 2.2, builder.position.y
    every(6, function()
      local out = answers(builder)
      for slot, name in ipairs({ "seb-ack", "seb-done", "seb-error" }) do
        local value, mine = out["virtual/" .. name] or 0, shown[name]
        if value ~= (mine and mine.value or 0) then
          if mine then
            erase(mine.objects)
            shown[name] = nil
          end
          if value ~= 0 then
            shown[name] = { value = value, objects = draw_signal(x + (slot - 1) * 2.6, y, name, value) }
          end
        end
      end
    end)
  end
]=]

-- A plan first: outlines and look-only ghosts, then the same project grown
-- for real. A pond in the third column of the second row closes that spot.
local PLANS = [=[
  camera(-6, 0.3, 1)
  tiles("water", -1, -2, 3, 2)
  network(-20, 0, 40, { { "solar-panel", 50 }, { "medium-electric-pole", 14 } })
  local area = { left = -16, top = -9, right = 12, bottom = 9 }
  local plan, selection
  at(0.3, function() selection = drag(area, GREEN, 0.9) end)
  at(1.3, function()
    selection.destroy()
    plan = grow { design = cell, area = area, dry_run = true, preview_ghosts = 4 }
  end)
  at(7, function() remote.call(MOD, "build_project", plan) end)
]=]

-- Two identical fills, ten copies wide and two deep; the lower one is ticked
-- Fast fill (open_early, up to eight copies in flight).
local FAST_FILL = [=[
  camera(-3.7, 0, 1)
  network(-19, 0, 100, { { "solar-panel", 50 } })
  caption(0, -8.7, "seb-tips.normal-fill", "Normal fill")
  caption(0, 8.7, "seb-tips.fast-fill", "Fast fill")
  at(0.5, function()
    grow { design = panel, area = { left = -15, top = -7, right = 15, bottom = -1 } }
    grow { design = panel, area = { left = -15, top = 1, right = 15, bottom = 7 }, open_early = true, max_building = 8 }
  end)
]=]

-- A field of version 1 becomes version 2 in place: the lamp of every copy
-- goes and an accumulator takes its place, the rest is left alone. Then a
-- third version makes the pole and the accumulator a fourth solar panel,
-- and the design names a research, Solar energy: the copies move on by
-- themselves when it is done. The design is registered afresh in every
-- pass, so its version numbers climb from pass to pass; the caption counts
-- the versions of this pass, and the research is taken away again so that
-- it can finish once more.
local UPDATES = [=[
  camera(-5.9, -0.7, 1.2)
  network(-16, 0, 30, { { "solar-panel", 30 }, { "medium-electric-pole", 8 }, { "small-lamp", 8 }, { "accumulator", 8 } })
  force.technologies["solar-energy"].researched = false
  local PANELS = {
    { name = "solar-panel", position = { 1.5, 1.5 } }, { name = "solar-panel", position = { 4.5, 1.5 } },
    { name = "solar-panel", position = { 1.5, 4.5 } },
  }
  local function version(...)
    local entities = {}
    for _, e in ipairs(PANELS) do entities[#entities + 1] = { name = e.name, position = e.position } end
    for _, e in ipairs({ ... }) do entities[#entities + 1] = e end
    return entities
  end
  local pole = { name = "medium-electric-pole", position = { 3.5, 3.5 } }
  local id = design(version(pole, { name = "small-lamp", position = { 4.5, 4.5 } }), "Solar cell")
  local field = grow { design = id, area = { left = -10, top = -6, right = 8, bottom = 6 }, open_early = true, max_building = 6 }
  local title = caption(-1, -7.8, "seb-tips.version", "Solar cell, version 1", "Solar cell", 1)
  local function versioned(number)
    title.text = { "?", { "seb-tips.version", "Solar cell", number }, "Solar cell, version " .. number }
  end
  at(4.5, function()
    design(version(pole, { name = "accumulator", position = { 5, 5 } }), "Solar cell")
    versioned(2)
  end)
  at(5.5, function() remote.call(MOD, "update_project", field) end)
  -- Version 3, and the research it waits for, named on the design.
  local status
  at(10, function()
    design(version({ name = "solar-panel", position = { 4.5, 4.5 } }), "Solar cell")
    versioned(3)
    remote.call(MOD, "set_upgrade_research", force, id, "solar-energy")
    status = rendering.draw_text { surface = surface, target = { -1, 7.6 }, text = { "?", { "seb-tips.waits-for", { "technology-name.solar-energy" } }, "Waiting for research" },
      color = { r = 1, g = 0.85, b = 0.2 }, scale = 2, scale_with_zoom = true, alignment = "center", vertical_alignment = "middle" }
  end)
  at(12.5, function()
    force.technologies["solar-energy"].researched = true
    status.text = { "?", { "seb-tips.researched", { "technology-name.solar-energy" } }, "Research done" }
    status.color = GREEN
  end)
]=]

-- A combinator program asks the builder to grow a row of four, and when the
-- builder says done, a column of two from its end. The program with its
-- request is bottom left, the builder with its answers beside it. X and Y
-- count tiles from the builder's tile (-8, 6) to the first copy's middle
-- tile: (11, -11) is the tile (3, -5), the middle of the row's first panel,
-- and (20, -8) the tile (12, -2), the middle of the column's first.
local BUILDER = [=[
  camera(0, -1, 1.3)
  network(-6, -4, 30, { { "solar-panel", 20 } })
  local builder, program = builder_at(-7.5, 6)
  readout(builder)
  at(1, function()
    send(program, { { "seb-grow", 1 }, { "seb-design", panel }, { "signal-X", 11 }, { "signal-Y", -11 }, { "seb-grow-east", 1 }, { "seb-count", 4 } })
  end)
  -- When the first growth is done the program waits a moment, so the answer
  -- can be read, and asks for the next.
  local second, waited = false, nil
  every(6, function()
    if second then return end
    if waited then
      waited = waited + 6
      if waited < 120 then return end
      second = true
      send(program, { { "seb-grow", 2 }, { "seb-design", panel }, { "signal-X", 20 }, { "signal-Y", -8 }, { "seb-grow-south", 1 }, { "seb-count", 2 } })
    elseif answers(builder)["virtual/seb-done"] == 1 then
      waited = 0
    end
  end)
]=]

-- One Stamp request puts a whole grid of copies down at once: five columns
-- and three rows, one tile apart, the first copy's middle at the tile (1, -7),
-- which is (9, -13) from the builder's tile (-8, 6).
local GRID = [=[
  camera(2, -0.5, 1.2)
  network(-6, -4, 40, { { "solar-panel", 20 } })
  local builder, program = builder_at(-7.5, 6)
  readout(builder)
  at(1, function()
    send(program, { { "seb-stamp", 1 }, { "seb-design", panel }, { "signal-X", 9 }, { "signal-Y", -13 },
      { "seb-grid-x", 5 }, { "seb-grid-y", 3 }, { "seb-spacing", 1 } })
  end)
]=]

-- Three copies of one design, each written a different recipe through its
-- port. The cell is built for real, far off screen, and captured, so that
-- its wire and its Set recipe setting are exactly what a player's blueprint
-- holds. Set recipe only picks a recipe the force has unlocked.
local PORTS = [=[
  for _, name in ipairs({ "iron-gear-wheel", "copper-cable", "pipe" }) do force.recipes[name].enabled = true end
  local cell
  do
    local assembler = surface.create_entity { name = "assembling-machine-2", position = { 41.5, 41.5 }, force = force }
    assembler.get_or_create_control_behavior().circuit_set_recipe = true
    local combinator = surface.create_entity { name = "constant-combinator", position = { 43.5, 40.5 }, force = force }
    surface.create_entity { name = "seb-port", position = { 43.5, 40.5 }, force = force }
    surface.create_entity { name = "medium-electric-pole", position = { 43.5, 42.5 }, force = force }
    combinator.get_wire_connector(defines.wire_connector_id.circuit_red, true)
      .connect_to(assembler.get_wire_connector(defines.wire_connector_id.circuit_red, true), false)
    local inventory = game.create_inventory(1)
    local stack = inventory[1]
    stack.set_stack { name = "blueprint" }
    stack.create_blueprint { surface = surface, force = force, area = { { 40, 40 }, { 44, 43 } } }
    stack.label = "Assembler cell"
    cell = remote.call(MOD, "register_design", force, stack.export_stack())
    inventory.destroy()
    for _, e in pairs(surface.find_entities_filtered { area = { { 40, 40 }, { 44, 43 } } }) do e.destroy() end
  end

  camera(-7.5, 1.25, 1.4)
  network(-17, -1, 30, { { "assembling-machine-2", 4 }, { "constant-combinator", 4 }, { "medium-electric-pole", 6 } })
  local copies = {}
  for i, x in ipairs({ -7, -1, 5 }) do
    copies[i] = stamp { design = cell, position = { x, 0.5 } }
    rendering.draw_text { surface = surface, target = { x, -2.5 }, text = { "seb-copies.copy", copies[i] }, color = { 1, 1, 1 },
      scale = 1.6, scale_with_zoom = true, alignment = "center", vertical_alignment = "middle" }
  end
  -- A pole that joins the copies' poles to the network.
  surface.create_entity { name = "medium-electric-pole", position = { -12.5, -2.5 }, force = force }
  local builder, program = builder_at(-4.5, 7.5)
  readout(builder)
  -- The write lands in the copy's constant combinator, its mailbox: a ring
  -- shows which one.
  local function write(number, copy, item)
    send(program, { { "seb-write", number }, { "seb-instance", copy }, { item, 1, "item" } })
    local box = remote.call(MOD, "get_instance", copy).footprint
    local mailbox = surface.find_entities_filtered { name = "constant-combinator", area = { { box.left, box.top }, { box.right, box.bottom } } }[1]
    if mailbox then pulse(mailbox.position.x, mailbox.position.y, { r = 1, g = 0.85, b = 0.2 }) end
  end
  at(4.5, function() write(1, copies[1], "iron-gear-wheel") end)
  at(6.5, function() write(2, copies[2], "copper-cable") end)
  at(8.5, function() write(3, copies[3], "pipe") end)
]=]

return {
  tip("seb-plans", "o", 1, { simulation = simulation(25, PLANS, CELL) }),
  tip("seb-fast-fill", "p", 1, { simulation = simulation(25, FAST_FILL, PANEL .. CAPTION) }),
  tip("seb-updates", "q", 1, { simulation = simulation(19, UPDATES, CAPTION) }),
  tip("seb-builder", "r", 1, { tag = "[item=seb-builder]", simulation = simulation(19, BUILDER, CIRCUIT .. PANEL) }),
  tip("seb-builder-grid", "s", 2, { simulation = simulation(10, GRID, CIRCUIT .. PANEL) }),
  tip("seb-ports", "t", 1, { tag = "[img=item/seb-port]", simulation = simulation(13, PORTS, CIRCUIT) }),
}
