-- The items growing puts in the cursor, and the window toggle. All are
-- only-in-cursor and never craftable:
--   seb-grow-blueprint  the chosen design in hand (Grow): a click grows it
--                       where its ghosts show (scripts/tool.lua)
--   seb-grow-tool       the area tool (Fill an area): a drag fills the
--                       rectangle, a click grows from there, a right-drag
--                       retires the instances it touches
--   seb-sensor-tool, seb-keep-clear-tool
--                       the marker tools: click or drag marks tiles,
--                       right-click or right-drag takes the marks off

local GRAPHICS = require("scripts.const").GRAPHICS

local function mode(color, box)
  return { border_color = color, cursor_box_type = box, mode = { "nothing" } }
end

-- The design in hand while growing: a blueprint the player can only hold.
local grow_blueprint = table.deepcopy(data.raw["blueprint"]["blueprint"])
grow_blueprint.name = "seb-grow-blueprint"
grow_blueprint.icons = nil
grow_blueprint.icon = GRAPHICS .. "grow-tool.png"
grow_blueprint.icon_size = 64
grow_blueprint.flags = { "only-in-cursor", "not-stackable" }
grow_blueprint.hidden = true
grow_blueprint.order = "z[self-expanding-blueprints]-c[grow-blueprint]"

data:extend({
  grow_blueprint,
  {
    type = "selection-tool",
    name = "seb-grow-tool",
    icon = GRAPHICS .. "grow-tool.png",
    icon_size = 64,
    stack_size = 1,
    flags = { "not-stackable", "only-in-cursor", "spawnable" },
    hidden = true,
    draw_label_for_cursor_render = true,
    subgroup = "tool",
    order = "z[self-expanding-blueprints]-a[grow-tool]",
    select = mode({ r = 0.30, g = 0.75, b = 0.35 }, "copy"),
    alt_select = mode({ r = 0.30, g = 0.75, b = 0.35 }, "copy"),
    reverse_select = mode({ r = 0.85, g = 0.28, b = 0.25 }, "not-allowed"),
    alt_reverse_select = mode({ r = 0.85, g = 0.28, b = 0.25 }, "not-allowed"),
  },
  -- Click a tile, drag a rectangle: ore sensors on it (marker_tools.lua).
  {
    type = "selection-tool",
    name = "seb-sensor-tool",
    icon = GRAPHICS .. "sensor.png",
    icon_size = 64,
    stack_size = 1,
    flags = { "not-stackable", "only-in-cursor", "spawnable" },
    hidden = true,
    subgroup = "tool",
    order = "z[self-expanding-blueprints]-b[sensor-tool]",
    -- Amber as the sensor; grey takes sensors off.
    select = mode({ r = 0.95, g = 0.70, b = 0.24 }, "copy"),
    alt_select = mode({ r = 0.95, g = 0.70, b = 0.24 }, "copy"),
    reverse_select = mode({ r = 0.75, g = 0.75, b = 0.75 }, "copy"),
    alt_reverse_select = mode({ r = 0.75, g = 0.75, b = 0.75 }, "copy"),
  },
  -- Click a tile, drag a rectangle: Keep clear markers on it (marker_tools.lua).
  {
    type = "selection-tool",
    name = "seb-keep-clear-tool",
    icon = GRAPHICS .. "clear.png",
    icon_size = 64,
    stack_size = 1,
    flags = { "not-stackable", "only-in-cursor", "spawnable" },
    hidden = true,
    subgroup = "tool",
    order = "z[self-expanding-blueprints]-b[keep-clear-tool]",
    -- Red as the marks and the deconstruction planner; grey takes marks off.
    select = mode({ r = 0.90, g = 0.22, b = 0.21 }, "not-allowed"),
    alt_select = mode({ r = 0.90, g = 0.22, b = 0.21 }, "not-allowed"),
    reverse_select = mode({ r = 0.75, g = 0.75, b = 0.75 }, "copy"),
    alt_reverse_select = mode({ r = 0.75, g = 0.75, b = 0.75 }, "copy"),
  },
  {
    type = "shortcut",
    name = "seb-toggle-window",
    action = "lua",
    associated_control_input = "seb-toggle-window",
    icon = GRAPHICS .. "grow-tool.png",
    icon_size = 64,
    small_icon = GRAPHICS .. "grow-tool.png",
    small_icon_size = 64,
    order = "f[self-expanding-blueprints]-a[window]",
  },
  {
    -- Not ALT + G: Factorio binds that to "give green wire", and both would
    -- fire, swapping whatever the player holds for a wire.
    type = "custom-input",
    name = "seb-toggle-window",
    key_sequence = "SHIFT + ALT + G",
    action = "lua",
    consuming = "none",
  },
})
