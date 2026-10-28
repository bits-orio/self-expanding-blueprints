-- Tips and Tricks entries about growing: the click, the sides and the count,
-- filling an area, what blocks a copy, replacing buildings, waiting for
-- materials and removing copies. Each has one simulation that runs the mod
-- itself (prototypes/tips/setup.lua says how a scene is written).

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

-- A 7 x 6 field cell: four solar panels and a pole at its east edge.
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

-- A 6 x 6 block of four solar panels.
local BLOCK = [=[
  local block = design({
    { name = "solar-panel", position = { 1.5, 1.5 } }, { name = "solar-panel", position = { 4.5, 1.5 } },
    { name = "solar-panel", position = { 1.5, 4.5 } }, { name = "solar-panel", position = { 4.5, 4.5 } },
  }, "Solar block")
]=]

return {
  -- One click grows a field until a lake stops it.
  tip("seb-grow", "a", 0, {
    is_title = true, tag = "[item=seb-grow-tool]",
    simulation = simulation(16, CELL .. [=[
      camera(-5, 1.5, 1)
      tiles("water", 9, -12, 13, 12)
      tiles("water", -16, 9, 13, 12)
      network(-19, 1, 30, { { "solar-panel", 40 }, { "medium-electric-pole", 12 } })
      at(0.5, function()
        pulse(-8.5, -6)
        grow { design = cell, point = { -8.5, -6 }, directions = { EAST, SOUTH } }
      end)
    ]=]),
  }),

  -- Which sides, and how many.
  tip("seb-grow-sides", "b", 1, {
    simulation = simulation(15, PANEL .. [=[
      camera(-3, 0, 1)
      network(-14, 6, 30, { { "solar-panel", 30 } })
      -- Four copies may be under construction at once, so the diamond is done
      -- while the picture is still up.
      -- East alone: a row of five.
      at(0.5, function()
        pulse(-18.5, -7.5)
        grow { design = panel, point = { -18.5, -7.5 }, directions = { EAST }, max_instances = 5, max_building = 4 }
      end)
      -- All four sides: a diamond of thirteen.
      at(1.5, function()
        pulse(7.5, 0.5)
        grow { design = panel, point = { 7.5, 0.5 }, directions = { NORTH, EAST, SOUTH, WEST }, max_instances = 13, max_building = 4 }
      end)
    ]=]),
  }),

  -- A drag fills its rectangle and stops at the edge.
  tip("seb-grow-area", "c", 1, {
    simulation = simulation(21, CELL .. [=[
      camera(-6, 0.5, 0.9)
      network(-22, 2, 40, { { "solar-panel", 50 }, { "medium-electric-pole", 14 } })
      local box = { left = -16, top = -9, right = 14, bottom = 10 }
      at(0.5, function() drag(box, GREEN, 0.6) end)
      at(1.1, function()
        grow { design = cell, area = box, directions = { EAST, SOUTH } }
      end)
    ]=]),
  }),

  -- A copy goes down whole or not at all.
  tip("seb-grow-obstacles", "d", 1, {
    simulation = simulation(19, CELL .. [=[
      camera(-5, 0, 0.95)
      network(-21, 0, 40, { { "solar-panel", 50 }, { "medium-electric-pole", 14 } })
      -- Trees and a rock on panel tiles: cleared. A pond and the player's own
      -- chest and belts: they close that spot.
      surface.create_entity { name = "tree-01", position = { -7.5, -7.5 } }
      surface.create_entity { name = "tree-02", position = { -4.5, -4.5 } }
      surface.create_entity { name = "huge-rock", position = { -14.5, 4.5 } }
      tiles("water", -1, -2, 3, 2)
      surface.create_entity { name = "iron-chest", position = { 7.5, 5.5 }, force = force }
      for x = 8.5, 10.5 do
        surface.create_entity { name = "transport-belt", position = { x, 5.5 }, direction = EAST, force = force }
      end
      local box = { left = -16, top = -9, right = 12, bottom = 9 }
      at(0.5, function() drag(box, GREEN, 0.5) end)
      at(1.0, function()
        grow { design = cell, area = box, directions = { EAST, SOUTH } }
      end)
    ]=]),
  }),

  -- The same buildings in the way: skipped, and replaced.
  tip("seb-superforce", "e", 2, {
    simulation = simulation(16, PANEL .. [=[
      camera(-7, 0, 1.2)
      network(-15, 0, 40, { { "solar-panel", 40 } })
      -- Old buildings of the player's in the lower row of each area.
      for _, y in ipairs({ -3.5, 6.5 }) do
        surface.create_entity { name = "wooden-chest", position = { -2.5, y }, force = force }
        for x = -1.5, -0.5 do
          surface.create_entity { name = "transport-belt", position = { x, y }, direction = EAST, force = force }
        end
        surface.create_entity { name = "small-electric-pole", position = { 3.5, y }, force = force }
        surface.create_entity { name = "small-lamp", position = { 4.5, y }, force = force }
      end
      local top = { left = -9, top = -8, right = 6, bottom = -2 }
      local bottom = { left = -9, top = 2, right = 6, bottom = 8 }
      at(0.5, function()
        drag(top, GREEN, 0.4)
        drag(bottom, GREEN, 0.4)
      end)
      at(1.0, function()
        grow { design = panel, area = top, directions = { EAST, SOUTH } }
        grow { design = panel, area = bottom, directions = { EAST, SOUTH }, superforce = true }
      end)
    ]=]),
  }),

  -- The materials gate: growth waits for panels and goes on when they come.
  tip("seb-grow-waiting", "f", 1, {
    simulation = simulation(17, BLOCK .. [=[
      camera(0, 1.5, 1.5)
      -- Two copies' worth of panels in the network's chest, and a chest with
      -- an inserter beside it that will bring more.
      network(0, 6, 30, { { "solar-panel", 8 } })
      local supply = surface.create_entity { name = "wooden-chest", position = { 4.5, 3.5 }, force = force }
      local inserter = surface.create_entity { name = "fast-inserter", position = { 3.5, 3.5 }, direction = WEST, force = force }
      if inserter.drop_position.x > inserter.position.x then inserter.direction = EAST end
      surface.create_entity { name = "small-electric-pole", position = { 3.5, 4.5 }, force = force }
      local box = { left = -12, top = -5, right = 12, bottom = 1 }
      at(0.5, function() drag(box, GREEN, 0.5) end)
      at(1.0, function()
        grow { design = block, area = box, directions = { EAST } }
      end)
      at(9, function()
        pulse(4.5, 3.5, { r = 1, g = 0.85, b = 0.2 })
        supply.insert { name = "solar-panel", count = 8 }
      end)
    ]=]),
  }),

  -- A right-drag takes out exactly the copies it touches.
  tip("seb-grow-remove", "g", 1, {
    simulation = simulation(11, BLOCK .. [=[
      camera(-5.5, -0.5, 1.3)
      network(-16, 1, 30, { { "solar-panel", 30 } })
      local ids = {}
      for _, p in ipairs({ { -7, -4 }, { 0, -4 }, { 7, -4 }, { -7, 3 }, { 0, 3 }, { 7, 3 } }) do
        ids[#ids + 1] = stamp { design = block, position = p }
      end
      -- The player's own pole and lamp in the walkway between the copies.
      surface.create_entity { name = "small-electric-pole", position = { -1.5, -0.5 }, force = force }
      surface.create_entity { name = "small-lamp", position = { 0.5, -0.5 }, force = force }
      -- Right-drag the middle column once the field stands.
      local box = { left = -3.5, top = -8, right = 3.5, bottom = 7 }
      local red
      at(4.5, function() red = drag(box, RED, 0.5) end)
      at(5.1, function()
        for _, id in ipairs(ids) do
          local footprint = remote.call(MOD, "get_instance", id).footprint
          if footprint.right > box.left and footprint.left < box.right
            and footprint.bottom > box.top and footprint.top < box.bottom then
            remote.call(MOD, "remove_instance", id)
          end
        end
      end)
      at(6.6, function() red.destroy() end)
    ]=]),
  }),
}
