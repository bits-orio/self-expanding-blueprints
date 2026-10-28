-- Blueprint builders in tests: a builder with a constant combinator wired to
-- its input, which plays the program, and what the builder answers.

local rig = require("lib.rig")

local builders = {}

-- A builder at `at` with its program two tiles west, wired red, for
-- rig.FORCE or `force` (a name).
function builders.place(surface, at, force)
  force = force or rig.FORCE
  local builder = surface.create_entity { name = "seb-builder", position = at, force = force, raise_built = true }
  local combinator = surface.create_entity { name = "constant-combinator", position = { at.x - 2, at.y + 0.5 }, force = force }
  combinator.get_wire_connector(defines.wire_connector_id.circuit_red, true)
    .connect_to(builder.get_wire_connector(defines.wire_connector_id.combinator_input_red, true), false)
  return builder, combinator
end

local function signal(name, count, kind)
  return { value = { type = kind or "virtual", name = name, quality = "normal", comparator = "=" }, min = count }
end

-- Replaces what the program holds: `fields` as virtual signals ({name =
-- count}), `items` as item signals.
function builders.send(combinator, fields, items)
  local filters = {}
  for name, count in pairs(fields) do filters[#filters + 1] = signal(name, count) end
  for name, count in pairs(items or {}) do filters[#filters + 1] = signal(name, count, "item") end
  combinator.get_or_create_control_behavior().get_section(1).filters = filters
end

-- The builder's output as {["virtual/seb-ack"] = n, ["item/solar-panel"] = n, ...}.
function builders.output(builder)
  local out = {}
  for _, s in ipairs(builder.get_signals(defines.wire_connector_id.combinator_output_red) or {}) do
    out[(s.signal.type or "item") .. "/" .. s.signal.name] = s.count
  end
  return out
end

-- Whether an output answers request `number` with ERR and that named error.
function builders.failed(out, number, error)
  return out["virtual/seb-error"] == number and out["virtual/seb-error-" .. error] == 1
end

-- A Stamp request for a size x size grid of copies, a tile apart.
function builders.grid(number, design, x, y, size)
  return { ["seb-stamp"] = number, ["seb-design"] = design, ["signal-X"] = x, ["signal-Y"] = y,
    ["seb-grid-x"] = size, ["seb-grid-y"] = size, ["seb-spacing"] = 1 }
end

-- What one search over a whole rectangle counts, per Sense category, as
-- Sense did before it went a chunk at a time: into `out` as output keys.
builders.COUNT = {
  ["seb-sense-entities"] = function(surface, area, force, out)
    for _, e in pairs(surface.find_entities_filtered { area = area, force = force }) do
      local items = e.type ~= "entity-ghost" and e.prototype.items_to_place_this
      local item = items and items[1] and "item/" .. items[1].name
      if item then out[item] = (out[item] or 0) + 1 end
    end
  end,
  ["seb-sense-resources"] = function(surface, area, _, out)
    for _, r in pairs(surface.find_entities_filtered { area = area, type = "resource" }) do
      for _, p in ipairs(r.prototype.mineable_properties.products or {}) do
        out[p.type .. "/" .. p.name] = (out[p.type .. "/" .. p.name] or 0) + r.amount
      end
    end
  end,
  ["seb-sense-trees"] = function(surface, area, _, out)
    out["virtual/seb-sense-trees"] = surface.count_entities_filtered { area = area, type = { "tree", "simple-entity" } }
  end,
}

-- The entity names of design `id` of `force`, read from its exported library.
function builders.design_entities(force, id)
  local name
  for _, row in ipairs(rig.call("list_designs", force)) do
    if row.id == id then name = row.name end
  end
  local inventory = game.create_inventory(1)
  inventory[1].import_stack(rig.call("export_library", force))
  local inner, names = inventory[1].get_inventory(defines.inventory.item_main), {}
  for i = 1, #inner do
    if inner[i].valid_for_read and inner[i].label == name then
      for _, e in ipairs(inner[i].get_blueprint_entities() or {}) do names[#names + 1] = e.name end
    end
  end
  inventory.destroy()
  return names
end

return builders
