-- The grow section of a design's page: the design's picture, its options in
-- groups (where it grows, how many copies, more options folded away), and
-- the Grow and Fill an area buttons, which put the design or the area tool
-- in the cursor.

local library = require("scripts.core.library")
local registry = require("scripts.core.registry")
local geometry = require("scripts.core.geometry")
local preview = require("scripts.gui.preview")
local layout = require("scripts.gui.layout")

local grow_view = {}

local NAME = "seb-grow"
local PICTURE = { width = 128, height = 112 }
-- The options beside the picture, within the window's width (window.WIDTH).
local COLUMN_WIDTH = 400

local DIRECTIONS = {
  { direction = geometry.NORTH, key = "north" },
  { direction = geometry.EAST, key = "east" },
  { direction = geometry.SOUTH, key = "south" },
  { direction = geometry.WEST, key = "west" },
}

local function checkbox(parent, key, state, action, enabled)
  parent.add {
    type = "checkbox", caption = { "seb-gui." .. key }, tooltip = { "seb-gui." .. key .. "-tooltip" },
    state = state == true, enabled = enabled ~= false, tags = { seb = action },
  }
end

-- Where it grows: the directions, or the design's own socket arrows.
local function where_group(column, options, drawn)
  local row = layout.row(column)
  row.add { type = "label", caption = { "seb-gui.directions" }, tooltip = { "seb-gui.directions-tooltip" } }
  for _, d in ipairs(DIRECTIONS) do
    row.add {
      type = "checkbox", caption = { "seb-gui.direction-" .. d.key }, enabled = not drawn,
      state = options.directions[d.direction] == true, tags = { seb = "grow-direction", direction = d.direction },
    }
  end
  checkbox(column, "world-directions", options.world_directions, "grow-world-directions", not drawn)
  if drawn then
    local note = column.add { type = "label", caption = { "seb-gui.uses-sockets" } }
    note.style.single_line = false
    note.style.maximal_width = COLUMN_WIDTH
  end
end

-- How many copies (growth and a plan each stop after a count of their own,
-- registry.grow_count), and whether each copy waits for its materials.
local function count_row(column, options)
  local plan = options.dry_run == true
  local key = plan and "seb-gui.plan-count" or "seb-gui.count"
  local row = layout.row(column)
  row.add { type = "label", caption = { key }, tooltip = { key .. "-tooltip" } }
  local count = registry.grow_count(options)
  local field = row.add {
    type = "textfield", numeric = true, allow_decimal = false, allow_negative = false, tooltip = { key .. "-tooltip" },
    text = count and tostring(count) or "", tags = { seb = plan and "grow-plan-count" or "grow-count" },
  }
  field.style.width = 60
  row.add { type = "label", caption = { "seb-gui.copies-unit" } }
  local gap = row.add { type = "empty-widget" }
  gap.style.width = 12
  checkbox(row, "materials", options.materials ~= false, "grow-materials")
end

-- The options most growth leaves alone, folded away unless opened; folded,
-- the row names the ones that are on, so none acts unseen.
local MORE = {
  { option = "superforce", key = "superforce", action = "grow-superforce" },
  { option = "retire_depleted", key = "retire-depleted", action = "grow-retire-depleted" },
  { option = "fast", key = "fast-fill", action = "grow-fast" },
  { option = "dry_run", key = "dry-run", action = "grow-dry-run" },
}

local function on_summary(options)
  local list = { "" }
  for _, m in ipairs(MORE) do
    if options[m.option] then
      if #list > 1 then list[#list + 1] = ", " end
      list[#list + 1] = { "seb-gui." .. m.key .. "-short" }
    end
  end
  return #list > 1 and { "seb-gui.more-on", list } or ""
end

-- Plan only's look-only ghosts, under it.
local function ghosts_row(column, options)
  local row = layout.row(column, 6)
  row.style.left_padding = 28
  local tooltip = { "seb-gui.preview-ghosts-tooltip" }
  row.add { type = "label", caption = { "seb-gui.preview-ghosts" }, tooltip = tooltip }
  local field = row.add {
    type = "textfield", numeric = true, allow_decimal = false, allow_negative = false,
    text = options.preview_ghosts and tostring(options.preview_ghosts) or "", tooltip = tooltip,
    enabled = options.dry_run == true, tags = { seb = "grow-preview-ghosts" },
  }
  field.style.width = 40
  row.add { type = "label", caption = { "seb-gui.preview-ghosts-after" }, tooltip = tooltip }
end

local function more_group(column, options)
  local open = options.more == true
  local row = layout.row(column, 6)
  row.add {
    type = "sprite-button", style = "tool_button", sprite = open and "utility/collapse" or "utility/expand",
    tooltip = { "seb-gui.more-options-tooltip" }, tags = { seb = "grow-more" },
  }
  row.add { type = "label", caption = { "seb-gui.more-options" }, tags = { seb = "grow-more" } }
  local on = row.add { type = "label", caption = on_summary(options) }
  on.style.font_color = { r = 0.6, g = 0.6, b = 0.6 }
  if not open then return end
  for _, m in ipairs(MORE) do checkbox(column, m.key, options[m.option], m.action) end
  ghosts_row(column, options)
end

-- Grow (the design in hand) and Fill an area (the area tool), side by side.
local function buttons(column, design)
  local ok = design.prepared and design.prepared.ok or false
  local row = layout.row(column)
  row.style.top_margin = layout.GROUP_GAP
  local grow = row.add {
    type = "button", style = "green_button", caption = { "seb-gui.grow" }, tooltip = { "seb-gui.grow-tooltip" },
    tags = { seb = "grow" }, enabled = ok,
  }
  grow.style.horizontally_stretchable = true
  local fill = row.add {
    type = "button", caption = { "seb-gui.fill-area" }, tooltip = { "seb-gui.area-tool-tooltip" },
    tags = { seb = "area-tool" }, enabled = ok,
  }
  fill.style.horizontally_stretchable = true
end

-- The chosen design's picture on the left, its options on the right.
local function fill(parent, player)
  local state = registry.player(player.index)
  local design = state.selected_design and library.get(player.force.index, state.selected_design)
  if not design then
    parent.add { type = "label", caption = { "seb-gui.pick-design" } }
    return
  end
  local body = layout.section(parent, { "seb-gui.grow-heading", design.name })
  local options = registry.grow_options(player.index)
  local drawn = design.prepared and design.prepared.ok and #design.prepared.sockets > 0
  local split = body.add { type = "flow", direction = "horizontal" }
  split.style.horizontal_spacing = layout.PAD
  preview.camera(split, player, design, PICTURE)
  local column = split.add { type = "flow", direction = "vertical" }
  column.style.maximal_width = COLUMN_WIDTH
  column.style.vertical_spacing = layout.ROW_GAP
  where_group(column, options, drawn)
  layout.divider(column)
  count_row(column, options)
  layout.divider(column)
  more_group(column, options)
  buttons(column, design)
end

function grow_view.build(parent, player)
  fill(parent.add { type = "flow", direction = "vertical", name = NAME }, player)
end

function grow_view.refresh(body, player)
  local holder = body[NAME]
  if not holder then return end
  holder.clear()
  fill(holder, player)
end

return grow_view
