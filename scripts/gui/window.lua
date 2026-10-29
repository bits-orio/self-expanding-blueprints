-- The Self-Expanding Blueprints window. Its front page lists the designs;
-- clicking one opens that design's page: its grow controls and its projects,
-- with a button back to the list. Projects of a deleted design stay on the
-- front page.
-- Each section redraws from the registry on its own, so a change elsewhere
-- never destroys an element another player is about to click or type into;
-- project rows update in place. Per-player choices live in storage.players.
-- Elements carry tags {seb = action, ...}; actions.lua routes the events.

local registry = require("scripts.core.registry")
local library = require("scripts.core.library")
local pools = require("scripts.core.pools")
local designs_view = require("scripts.gui.designs_view")
local grow_view = require("scripts.gui.grow_view")
local projects_view = require("scripts.gui.projects_view")
local projects = require("scripts.core.projects")
local preview = require("scripts.gui.preview")
local outlines = require("scripts.gui.outlines")
local layout = require("scripts.gui.layout")
local copies_view = require("scripts.gui.copies_view")
local scheduler = require("scripts.core.scheduler")

local window = {}

window.WIDTH = 580

local NAME = "seb-window"
window.NAME = NAME

local function frame_of(player)
  return player.gui.screen[NAME]
end
window.frame_of = frame_of

local function title_bar(frame)
  local bar = frame.add { type = "flow", direction = "horizontal" }
  bar.drag_target = frame
  bar.add { type = "label", caption = { "seb-gui.title" }, style = "frame_title", ignored_by_interaction = true }
  local filler = bar.add { type = "empty-widget", style = "draggable_space_header", ignored_by_interaction = true }
  filler.style.horizontally_stretchable = true
  filler.style.height = 24
  bar.add {
    type = "sprite-button", style = "frame_action_button", sprite = "utility/close",
    tooltip = { "seb-gui.close" }, tags = { seb = "close" },
  }
end

-- The design whose page the player has open, if any.
local function open_design(player)
  local state = registry.player(player.index)
  if not (state.design_open and state.selected_design) then return nil end
  return library.get(player.force.index, state.selected_design)
end

-- The way back to the list, and the open design's name to rename it by.
local function back_bar(parent, design)
  local bar = parent.add { type = "flow", direction = "horizontal" }
  bar.style.padding = { 8, layout.PAD, 8, layout.PAD }
  bar.style.vertical_align = "center"
  bar.style.horizontal_spacing = 8
  bar.add {
    type = "button", style = "back_button", caption = { "seb-gui.back-to-designs" },
    tooltip = { "seb-gui.back-to-designs-tooltip" }, tags = { seb = "back-to-designs" },
  }
  bar.add { type = "sprite", sprite = "utility/rename_icon", tooltip = { "seb-gui.rename-tooltip" } }
  local name = bar.add {
    type = "textfield", text = design.name, tooltip = { "seb-gui.rename-tooltip" }, lose_focus_on_confirm = true,
    tags = { seb = "rename-design", design = design.id },
  }
  name.style.width = 360
end

-- The pools the open design is in, as names to edit: a socket naming one
-- can build the design.
local function pools_bar(parent, design)
  local bar = parent.add { type = "flow", direction = "horizontal" }
  bar.style.padding = { 0, layout.PAD, 8, layout.PAD }
  bar.style.vertical_align = "center"
  bar.style.horizontal_spacing = 8
  bar.add { type = "label", caption = { "seb-gui.pools" }, tooltip = { "seb-gui.pools-tooltip" } }
  local field = bar.add {
    type = "textfield", text = table.concat(pools.of(design), ", "), tooltip = { "seb-gui.pools-tooltip" },
    lose_focus_on_confirm = true, tags = { seb = "set-pools", design = design.id },
  }
  field.style.width = 360
end

-- The sections scroll inside the body, which is never taller than the
-- screen: with many designs and projects the window still fits.
local function fill(player, frame)
  local body = frame.add { type = "frame", style = "inside_shallow_frame", direction = "vertical", name = "body" }
  body.style.width = window.WIDTH
  local sections = body.add {
    type = "scroll-pane", name = "sections", style = "naked_scroll_pane",
    vertical_scroll_policy = "auto", horizontal_scroll_policy = "never",
  }
  sections.style.maximal_height = math.max(300, math.floor(player.display_resolution.height / player.display_scale) - 160)
  local design = open_design(player)
  if design then
    back_bar(sections, design)
    pools_bar(sections, design)
    grow_view.build(sections, player)
  else
    designs_view.build(sections, player)
  end
  projects_view.build(sections, player)
end

-- Where the sections live: views look their holders up in it.
local function sections_of(frame)
  return frame and frame.body and frame.body.sections
end

function window.open(player)
  local frame = frame_of(player)
  if frame then frame.destroy() end
  frame = player.gui.screen.add { type = "frame", name = NAME, direction = "vertical" }
  title_bar(frame)
  fill(player, frame)
  local state = registry.player(player.index)
  if state.window_location then frame.location = state.window_location else frame.force_auto_center() end
  player.opened = frame
end

function window.close(player)
  preview.hide(player)
  outlines.unhover(player)
  copies_view.close(player)
  local frame = frame_of(player)
  if not frame then return end
  registry.player(player.index).window_location = frame.location
  frame.destroy()
end

-- Factorio closes what a player has open when their view changes (locating
-- a project moves it to the map): around fn, a close of the window is kept
-- from closing it, and it is the player's open window again after.
local keeping
function window.keep_open(player, fn)
  keeping = player.index
  local result = fn()
  keeping = nil
  local frame = frame_of(player)
  if frame and player.opened ~= frame then player.opened = frame end
  return result
end

function window.kept(player)
  return keeping == player.index
end

-- Factorio also closes what a player has open when they enter or leave
-- remote view. Whichever of the close and the view change comes first, the
-- second of the same tick undoes the close: the window stays where it was,
-- and is the player's open window again next tick (set within the change,
-- it does not hold), so Escape still closes it.
local function keep_after_view_change(player)
  if not frame_of(player) then window.open(player) end
  scheduler.at(game.tick + 1, { kind = "window-opened", player_index = player.index })
end

scheduler.register("window-opened", function(item)
  local player = game.get_player(item.player_index)
  local frame = player and frame_of(player)
  if frame and player.opened ~= frame then player.opened = frame end
end)

function window.on_closed(player)
  local state = registry.player(player.index)
  if state.view_changed_tick == game.tick then return keep_after_view_change(player) end
  if frame_of(player) then state.window_closed_tick = game.tick end
  window.close(player)
end

function window.on_view_changed(player)
  local state = registry.player(player.index)
  state.view_changed_tick = game.tick
  if state.window_closed_tick == game.tick then keep_after_view_change(player) end
end

function window.toggle(player)
  if frame_of(player) then window.close(player) else window.open(player) end
end

-- Rebuilds the body in place, keeping the window where it is.
function window.refresh(player)
  local frame = frame_of(player)
  if not frame then return end
  preview.hide(player)
  outlines.unhover(player)
  if frame.body then frame.body.destroy() end
  fill(player, frame)
end

-- Calls fn(body, player) for every player of the force with the window open.
local function each_open(force_index, fn)
  local force = game.forces[force_index]
  if not force then return end
  for _, player in pairs(force.connected_players) do
    local frame = frame_of(player)
    local sections = sections_of(frame)
    if sections then fn(sections, player) end
  end
end

-- The design's page, or the list of designs.
function window.open_design(player, design_id)
  local state = registry.player(player.index)
  state.selected_design, state.design_open = design_id, true
  window.refresh(player)
end

function window.show_designs(player)
  registry.player(player.index).design_open = false
  window.refresh(player)
end

-- After a design was renamed: every open window of the force, whole, and
-- its copies panels.
function window.refresh_force(force_index)
  each_open(force_index, function(_, player)
    window.refresh(player)
    copies_view.refresh(player)
  end)
end

-- After a grow option that changes what the section shows (Plan only).
function window.refresh_grow(player)
  local sections = sections_of(frame_of(player))
  if sections then grow_view.refresh(sections, player) end
end

-- The cursor changed: the add button says what it would add.
function window.cursor_changed(player)
  local frame = frame_of(player)
  local sections = sections_of(frame)
  if sections then designs_view.refresh_cursor(sections, player) end
end

-- After a design was added, updated or deleted: every open window of the
-- force redraws its designs, and its grow section only if that showed the
-- design (or a design that is gone).
function window.refresh_designs(force_index, design_id)
  each_open(force_index, function(body, player)
    preview.hide(player)
    local state = registry.player(player.index)
    -- The front page whole: the list, and projects of a design just deleted.
    if not state.design_open then return window.refresh(player) end
    if not open_design(player) then return window.show_designs(player) end
    -- A new version can make copies outdated: their rows offer an update.
    -- In place, so no click in flight on a row is lost.
    for _, project in ipairs(projects.list(force_index)) do projects_view.refresh_row(body, player, project) end
    local selected = registry.player(player.index).selected_design
    if selected == design_id or (selected and not library.get(force_index, selected)) then
      grow_view.refresh(body, player)
    end
  end)
end

-- After a project changed: its row in every open window of the force, only
-- when what the row shows has changed.
function window.refresh_project(project)
  local key = projects_view.key(project)
  if project.shown_key == key then return end
  project.shown_key = key
  each_open(project.force_index, function(body, player) projects_view.refresh_row(body, player, project) end)
end

-- After records were dropped without their own events: the projects of the
-- forces that lost one (a surface deleted), or every open window, whole
-- (forces merged, a team released).
function window.refresh_dropped(forces)
  if not forces then
    for _, player in pairs(game.connected_players) do window.refresh(player) end
    return
  end
  for force_index in pairs(forces) do each_open(force_index, projects_view.refresh) end
end

return window
