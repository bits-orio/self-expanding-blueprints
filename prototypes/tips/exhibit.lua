-- What the scenes about drawn markers add to setup.TOOLS, as Lua code to paste
-- after it (a simulation cannot require anything). Locals it defines:
--   book(label, entries)     a blueprint book registered as a pool; entries are
--                            { { label, entities }, ... }; returns the design ids
--   exhibit(entities, x, y)  a build as the player draws it, markers too so the
--                            arrows show, on a blueprint-blue area; (x, y) is
--                            where the blueprint's origin goes
--   note(text, x, y, alignment)  a small label: a design's name, or a name the
--                            mod already has in its locale ({ "item-name.seb-entry" })
--   WHITE                    the colour of labels
-- The entities are the tables `design` takes, with positions as { x, y }. Colours
-- are premultiplied, so see-through ones go through TOOLS' `tint`.

local exhibit = {}

exhibit.TOOLS = [=[
  local WHITE = { r = 1, g = 1, b = 1 }
  local BLUEPRINT = { r = 0.30, g = 0.60, b = 1.0 }

  local function book(label, entries)
    local inventory = game.create_inventory(1)
    local stack = inventory[1]
    stack.set_stack { name = "blueprint-book" }
    stack.label = label
    local inner = stack.get_inventory(defines.inventory.item_main)
    for i, entry in ipairs(entries) do
      inner.insert { name = "blueprint" }
      for j, e in ipairs(entry[2]) do e.entity_number = j end
      inner[i].set_blueprint_entities(entry[2])
      inner[i].label = entry[1]
    end
    local ids = remote.call(MOD, "register_design", force, stack.export_stack())
    inventory.destroy()
    return ids
  end

  -- The tile box the entities cover, in blueprint coordinates.
  local function extent(entities)
    local left, top, right, bottom = math.huge, math.huge, -math.huge, -math.huge
    for _, e in ipairs(entities) do
      local proto = prototypes.entity[e.name]
      local w, h = proto.tile_width, proto.tile_height
      if e.direction == EAST or e.direction == WEST then w, h = h, w end
      left, top = math.min(left, e.position[1] - w / 2), math.min(top, e.position[2] - h / 2)
      right, bottom = math.max(right, e.position[1] + w / 2), math.max(bottom, e.position[2] + h / 2)
    end
    return left, top, right, bottom
  end

  local function exhibit(entities, x, y)
    for _, e in ipairs(entities) do
      surface.create_entity { name = e.name, position = { x + e.position[1], y + e.position[2] }, direction = e.direction, force = force }
    end
    local left, top, right, bottom = extent(entities)
    local from, to = { x + left - 0.5, y + top - 0.5 }, { x + right + 0.5, y + bottom + 0.5 }
    rendering.draw_rectangle { surface = surface, left_top = from, right_bottom = to, filled = true,
      color = tint(BLUEPRINT, 0.45), draw_on_ground = true }
    rendering.draw_rectangle { surface = surface, left_top = from, right_bottom = to, filled = false, width = 2,
      color = tint(BLUEPRINT, 0.9), draw_on_ground = true }
  end

  local function note(text, x, y, alignment)
    rendering.draw_text { surface = surface, text = text, target = { x, y }, scale = 1.2,
      color = WHITE, alignment = alignment or "left", vertical_alignment = "middle" }
  end
]=]

return exhibit
