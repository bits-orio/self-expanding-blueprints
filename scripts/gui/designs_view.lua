-- The designs section: the force's library, one row per design, plus the
-- button that adds the blueprint in hand (its caption follows the cursor),
-- the buttons that hand out markers, and the question mark that opens "How
-- growing works" in its own window (help_view.lua). Hovering a design shows
-- a picture of it (preview.lua).

local const = require("scripts.const")
local layout = require("scripts.gui.layout")
local library = require("scripts.core.library")
local projects = require("scripts.core.projects")
local twins = require("scripts.core.twins")
local books = require("scripts.core.books")
local registry = require("scripts.core.registry")
local cursor = require("scripts.cursor")
local design_text = require("scripts.gui.design_text")

local designs_view = {}

local NAME = "seb-designs"
local BODY = "seb-designs-body"
local ADD = "seb-add"

local SPRITE_TYPE = { virtual = "virtual-signal" }

function designs_view.icon_sprite(signal)
  if not (signal and signal.name) then return "item/blueprint" end
  local kind = signal.type or "item"
  local path = (SPRITE_TYPE[kind] or kind) .. "/" .. signal.name
  return helpers.is_valid_sprite_path(path) and path or "item/blueprint"
end

-- What the add button offers for a book: its blueprints, counted by a walk
-- that stops at the ceiling (books.lua), so a huge book costs no more to
-- hold than one at the ceiling.
local function book_offer(source, tooltip)
  local list, over = books.blueprints_in(source)
  if over then return { caption = { "seb-gui.add-book-too-big", const.MAX_BOOK_CHILDREN }, tooltip = tooltip } end
  return { caption = { "seb-gui.add-book", #list }, tooltip = tooltip, enabled = #list > 0 }
end

-- What the add button offers for what the player holds.
local function offer(player)
  local source = cursor.blueprint(player)
  if not source then return { caption = { "seb-gui.add-nothing" }, tooltip = { "seb-gui.add-nothing-tooltip" } } end
  local tooltip = { "seb-gui.add-tooltip" }
  if not books.is_single_blueprint(source) then return book_offer(source, tooltip) end
  if not source.is_blueprint_setup() then return { caption = { "seb-gui.add-empty" }, tooltip = tooltip } end
  local label = source.label
  if not label or label == "" then return { caption = { "seb-gui.add-unnamed" }, tooltip = tooltip, enabled = true } end
  if library.find(player.force.index, label, true) then
    return { caption = { "seb-gui.add-update", label }, tooltip = tooltip, enabled = true }
  end
  return { caption = { "seb-gui.add-named", label }, tooltip = tooltip, enabled = true }
end

local function show_offer(button, player)
  local o = offer(player)
  button.caption, button.tooltip, button.enabled = o.caption, o.tooltip, o.enabled == true
end

local function marker_button(flow, item, caption, tooltip, action)
  local button = flow.add {
    type = "button", caption = { caption }, tooltip = { tooltip }, tags = { seb = action or "give-marker", item = item },
  }
  button.style.minimal_width = 0
  button.style.horizontal_align = "left"
  button.style.left_padding = 4
  button.style.right_padding = 4
end

-- The title row with the help button, the add button, then the row of
-- markers to draw into a build.
local function header(parent, bar, player)
  local pusher = bar.add { type = "empty-widget" }
  pusher.style.horizontally_stretchable = true
  bar.add {
    type = "sprite-button", style = "tool_button", sprite = "item/blueprint-book",
    tooltip = { "seb-gui.export-library" }, tags = { seb = "export-library" },
  }
  bar.add {
    type = "sprite-button", style = "tool_button", sprite = "utility/questionmark",
    tooltip = { "seb-gui.help-tooltip" }, tags = { seb = "toggle-help" },
  }
  local add = parent.add { type = "button", name = ADD, tags = { seb = "add-design" } }
  add.style.horizontally_stretchable = true
  show_offer(add, player)
  local draw = layout.row(parent, 6)
  draw.add { type = "label", caption = { "seb-gui.draw" }, tooltip = { "seb-gui.draw-tooltip" } }
  marker_button(draw, const.SOCKET, "seb-gui.give-socket", "seb-gui.give-socket-tooltip")
  marker_button(draw, const.ENTRY, "seb-gui.give-entry", "seb-gui.give-entry-tooltip")
  marker_button(draw, const.SENSOR_TOOL, "seb-gui.give-sensor", "seb-gui.give-sensor-tooltip", "give-marker-tool")
  marker_button(draw, const.PROBE, "seb-gui.give-probe", "seb-gui.give-probe-tooltip")
  marker_button(draw, const.PORT, "seb-gui.give-port", "seb-gui.give-port-tooltip")
  marker_button(draw, const.CLEAR_TOOL, "seb-gui.give-clear", "seb-gui.give-clear-tooltip", "give-marker-tool")
end

-- The picture card that hovering shows says the rest (preview.lua).
-- How many running projects each design has, by design id.
local function project_counts(force_index)
  local counts = {}
  for _, project in ipairs(projects.list(force_index)) do
    if project.state ~= const.PROJECT_STATE.stopped then
      local origin = twins.origin_id(force_index, project.design_id)
      counts[origin] = (counts[origin] or 0) + 1
    end
  end
  return counts
end

local function row(grid, design, selected, count)
  local tooltip = { "seb-gui.select-design" }
  local tags = { seb = "select-design", design = design.id }
  grid.add {
    type = "sprite-button", style = selected and "yellow_slot_button" or "slot_button",
    sprite = designs_view.icon_sprite(design.icon), tooltip = tooltip, tags = tags, raise_hover_events = true,
  }
  local name = grid.add { type = "button", caption = design.name, tooltip = tooltip, tags = tags, raise_hover_events = true }
  name.style.width = 140
  name.style.horizontal_align = "left"
  if selected then name.style.font = "default-bold" end
  local growth = grid.add { type = "label", caption = design_text.describe(design) }
  growth.style.width = 160
  local projects_label = grid.add { type = "label", caption = count > 0 and { "seb-gui.design-projects", count } or "" }
  projects_label.style.width = 70
  local chooser = grid.add {
    type = "choose-elem-button", elem_type = "technology", technology = design.upgrade_on, style = "slot_button",
    tooltip = { "seb-gui.upgrade-on" }, tags = { seb = "upgrade-on", design = design.id },
  }
  chooser.style.size = 28
  grid.add {
    type = "sprite-button", style = "tool_button", sprite = "utility/refresh",
    tooltip = { "seb-gui.update-from-cursor" }, tags = { seb = "update-design", design = design.id },
  }
  grid.add {
    type = "sprite-button", style = "tool_button_red", sprite = "utility/trash",
    tooltip = { "seb-gui.delete-design" }, tags = { seb = "delete-design", design = design.id },
  }
end

local function fill(holder, player)
  local body, bar = layout.section(holder, { "seb-gui.designs" }, BODY)
  header(body, bar, player)
  local list = library.list(player.force.index)
  if #list == 0 then
    local hint = body.add { type = "label", caption = { "seb-gui.no-designs" } }
    hint.style.single_line = false
    return
  end
  local hint = body.add { type = "label", caption = { "seb-gui.designs-hint" } }
  hint.style.font_color = { r = 0.7, g = 0.7, b = 0.7 }
  local pane = body.add { type = "scroll-pane", style = "naked_scroll_pane", vertical_scroll_policy = "auto" }
  local grid = pane.add { type = "table", column_count = 7 }
  grid.style.vertical_align = "center"
  grid.style.horizontal_spacing = 8
  grid.style.vertical_spacing = 6
  local selected = registry.player(player.index).selected_design
  local counts = project_counts(player.force.index)
  for _, design in ipairs(list) do row(grid, design, design.id == selected, counts[design.id] or 0) end
  -- A rebuilt list scrolls to the top; keep the chosen design in view.
  for _, child in pairs(grid.children) do
    if child.tags.seb == "select-design" and child.tags.design == selected and child.type == "sprite-button" then
      pane.scroll_to_element(child)
      break
    end
  end
end

function designs_view.build(parent, player)
  fill(parent.add { type = "flow", direction = "vertical", name = NAME }, player)
end

function designs_view.refresh(body, player)
  local holder = body[NAME]
  if not holder then return end
  holder.clear()
  fill(holder, player)
end

-- The cursor changed: only the add button's caption follows it.
function designs_view.refresh_cursor(body, player)
  local holder = body[NAME]
  local button = holder and holder[BODY] and holder[BODY][ADD]
  if button then show_offer(button, player) end
end

return designs_view
