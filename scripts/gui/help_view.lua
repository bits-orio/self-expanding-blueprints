-- "How growing works": a window of its own with a tab for each marker a
-- player draws into a build (sockets and plugs, ore sensors, probes, ports),
-- each a picture and a few lines. It is never the player's opened GUI, so it
-- stays up beside the main window, and while they draw a build on the map
-- with the main window closed. The title bar drags it; it reopens where it
-- was left, on the tab last shown. Tips and Tricks holds the long form, with
-- live examples (prototypes/tips.lua): each tab's button puts a [tip=...]
-- link to its entry in the player's chat, the only place such a link opens
-- Tips and Tricks when clicked (not in a GUI label, and no API opens it).
-- A mod window cannot be resized, so this one is the quick reference.

local registry = require("scripts.core.registry")

local help_view = {}

local NAME = "seb-help-window"
help_view.NAME = NAME

local PICTURE_W = 400   -- GUI units, so pictures scale with the interface like the text
local TEXT_W = 410
local EDGE = 16         -- pixels kept from the screen's right edge on first open
local TOP = 380         -- GUI units from the top on first open: under the minimap
local CHROME = 230      -- GUI units the title, tabs and footer take beside a page
local GRIP = 100        -- GUI units of the title bar kept on screen, so it can be dragged back
local TYPICAL = 680     -- GUI units a full window usually takes, for where it first opens

-- Each tab: its caption, its picture (a sprite and its height for a 400
-- wide picture), its lines (all in [seb-gui]) and the Tips and Tricks entry
-- with its live example (prototypes/tips.lua).
local TABS = {
  { caption = "help-tab-sockets", sprite = "seb-help-growth", height = 80, tip = "seb-sockets",
    lines = { "help-plain", "help-socket", "help-plug", "help-target" } },
  { caption = "help-tab-sensor", sprite = "seb-help-sensor", height = 80, tip = "seb-mining",
    lines = { "help-sensor-what", "help-sensor-where", "help-sensor-radius", "help-sensor-retire" } },
  { caption = "help-tab-probe", sprite = "seb-help-probe", height = 112, tip = "seb-probes",
    lines = { "help-probe-what", "help-probe-rules", "help-probe-examples", "help-probe-pools" } },
  { caption = "help-tab-port", sprite = "seb-help-port", height = 80, tip = "seb-ports",
    lines = { "help-port-what", "help-port-how", "help-port-numbers" } },
  { caption = "help-tab-clear", sprite = "seb-help-clear", height = 80, tip = "seb-keep-clear",
    lines = { "help-clear-what", "help-clear-how", "help-clear-footprint", "help-clear-negative-space" } },
}
help_view.TABS = TABS

local function frame_of(player)
  return player.gui.screen[NAME]
end

local function title_bar(frame)
  local bar = frame.add { type = "flow", direction = "horizontal" }
  bar.drag_target = frame
  bar.add { type = "label", caption = { "seb-gui.help" }, style = "frame_title", ignored_by_interaction = true }
  local filler = bar.add { type = "empty-widget", style = "draggable_space_header", ignored_by_interaction = true }
  filler.style.horizontally_stretchable = true
  filler.style.height = 24
  bar.add {
    type = "sprite-button", style = "frame_action_button", sprite = "utility/close",
    tooltip = { "seb-gui.close" }, tags = { seb = "close-help" },
  }
end

local function wrapped(parent, caption)
  local label = parent.add { type = "label", caption = caption }
  label.style.single_line = false
  label.style.maximal_width = TEXT_W
  return label
end

-- The tallest a page may be: the window then fits the screen, and a long
-- page scrolls.
local function page_height(player)
  return math.max(160, math.floor(player.display_resolution.height / player.display_scale) - CHROME - 40)
end

local function page(tabs, tab, height)
  local scroll = tabs.add { type = "scroll-pane", style = "naked_scroll_pane", horizontal_scroll_policy = "never" }
  scroll.style.maximal_height = height
  local flow = scroll.add { type = "flow", direction = "vertical" }
  flow.style.vertical_spacing = 6
  local centre = flow.add { type = "flow", direction = "horizontal" }
  centre.style.horizontal_align = "center"
  centre.style.horizontally_stretchable = true
  local picture = centre.add { type = "sprite", sprite = tab.sprite, resize_to_sprite = false }
  picture.style.width, picture.style.height = PICTURE_W, tab.height
  picture.style.stretch_image_to_widget_size = true
  for _, key in ipairs(tab.lines) do wrapped(flow, { "seb-gui." .. key }) end
  if tab.tip then
    flow.add {
      type = "button", caption = { "seb-gui.help-live" }, tooltip = { "seb-gui.help-live-tooltip" },
      tags = { seb = "help-tip", tip = tab.tip },
    }
  end
  return scroll
end

local function fill(frame, selected, height)
  local body = frame.add { type = "frame", style = "inside_deep_frame", direction = "vertical" }
  local tabs = body.add { type = "tabbed-pane", tags = { seb = "help-tab" } }
  for _, tab in ipairs(TABS) do
    local header = tabs.add { type = "tab", caption = { "seb-gui." .. tab.caption } }
    tabs.add_tab(header, page(tabs, tab, height))
  end
  tabs.selected_tab_index = math.min(selected or 1, #TABS)
  local footer = frame.add { type = "flow", direction = "vertical" }
  footer.style.top_padding = 4
  wrapped(footer, { "seb-gui.help-markers" })
end

-- First open: against the right edge of the screen, below the minimap and
-- out of the main window's way, as far down as the window still fits.
local function first_location(player)
  local resolution, scale = player.display_resolution, player.display_scale
  local lowest = resolution.height - math.floor(TYPICAL * scale)
  return {
    x = math.max(0, resolution.width - math.floor((TEXT_W + 40) * scale) - EDGE),
    y = math.max(0, math.min(math.floor(TOP * scale), lowest)),
  }
end

-- A place saved on a bigger screen (or another scale) is pulled back, so
-- some of the title bar always stays on screen to drag the window by.
local function on_screen(player, location)
  local resolution, scale = player.display_resolution, player.display_scale
  return {
    x = math.max(0, math.min(location.x, resolution.width - math.floor(GRIP * scale))),
    y = math.max(0, math.min(location.y, resolution.height - math.floor(GRIP * scale))),
  }
end

function help_view.open(player)
  local frame = frame_of(player)
  if frame then frame.destroy() end
  local state = registry.player(player.index)
  local height = page_height(player)
  frame = player.gui.screen.add { type = "frame", name = NAME, direction = "vertical" }
  title_bar(frame)
  fill(frame, state.help_tab, height)
  frame.location = state.help_location and on_screen(player, state.help_location) or first_location(player)
end

function help_view.close(player)
  local frame = frame_of(player)
  if not frame then return end
  registry.player(player.index).help_location = frame.location
  frame.destroy()
end

function help_view.toggle(player)
  if frame_of(player) then help_view.close(player) else help_view.open(player) end
end

-- Drawn afresh where it stands (a new version's text, a new display scale).
function help_view.refresh(player)
  local frame = frame_of(player)
  if not frame then return end
  registry.player(player.index).help_location = frame.location
  help_view.open(player)
end

function help_view.on_location_changed(event)
  local element = event.element
  if not (element and element.valid and element.name == NAME) then return end
  registry.player(event.player_index).help_location = element.location
end

function help_view.on_tab_changed(event)
  local element = event.element
  if not (element and element.valid and element.tags.seb == "help-tab") then return end
  registry.player(event.player_index).help_tab = element.selected_tab_index
end

return help_view
