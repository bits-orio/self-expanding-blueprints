-- Event wiring only: every handler lives in a module under scripts/.
-- No unconditional on_tick. Work runs from engine events and one due-tick
-- queue (scripts/core/scheduler.lua), whose handler on_load re-registers from
-- storage alone, so every peer in a multiplayer game holds the same handlers.

local const = require("scripts.const")
local registry = require("scripts.core.registry")
local scheduler = require("scripts.core.scheduler")
local stale = require("scripts.core.stale")
local projects = require("scripts.core.projects")
require("scripts.core.copy_events")
local loop = require("scripts.core.loop")
local growth = require("scripts.core.growth")
local overlay = require("scripts.render.overlay")
local depletion = require("scripts.core.depletion")
local research = require("scripts.core.research")
local tracking = require("scripts.core.tracking")
local stamp = require("scripts.core.stamp")
local lifecycle = require("scripts.lifecycle")
local limit_changes = require("scripts.limit_changes")
local migrations = require("scripts.migrations")
local window = require("scripts.gui.window")
local actions = require("scripts.gui.actions")
local tool = require("scripts.tool")
local markers = require("scripts.markers")
local marker_tools = require("scripts.marker_tools")
local labs = require("scripts.core.labs")
local mts = require("scripts.compat.mts")
local builder = require("scripts.circuit.builder")
local builder_view = require("scripts.gui.builder_view")
local help_view = require("scripts.gui.help_view")
local outlines = require("scripts.gui.outlines")
require("scripts.remote.interface")

projects.hooks.changed = window.refresh_project
overlay.hooks.preview = growth.preview
lifecycle.hooks.dropped = window.refresh_dropped
research.hooks.updated = function(force_index, design, done, refused)
  local force = game.forces[force_index]
  if force and done + refused > 0 then force.print({ "seb-message.research-updated", design.name, done, refused }) end
  window.refresh_designs(force_index, design.id)
end

script.on_init(function()
  registry.init_storage()
  mts.subscribe()
end)

script.on_configuration_changed(function()
  registry.init_storage()
  migrations.run()
  -- Prototypes may have changed under the designs (entity sizes, our own
  -- markers): every design is prepared again, a few at a time, and at once
  -- when one is used before its turn (stale.lua).
  stale.mark_all()
  -- A window saved open was built by the old version: draw it afresh.
  for _, player in pairs(game.players) do
    window.refresh(player)
    help_view.refresh(player)
  end
end)

script.on_load(function()
  scheduler.on_load()
  mts.subscribe()
end)

-- Completion tracking: every build path hands back the ghost's tags. A
-- blueprint builder can come up through any of them too.
local function built(event)
  tracking.on_built(event)
  builder.on_built(event)
end
script.on_event(defines.events.on_built_entity, function(event)
  built(event)
  markers.on_built_entity(event)
end)
script.on_event(defines.events.on_robot_built_entity, built)
script.on_event(defines.events.script_raised_revive, built)
script.on_event(defines.events.on_space_platform_built_entity, built)
script.on_event(defines.events.on_entity_cloned, builder.on_built, { { filter = "name", name = const.BUILDER } })
-- Only our own marker ghosts and builders matter here; the filter keeps the
-- engine from building an event table for every ghost a stamp (or any other
-- script) raises.
local raised_filters = { { filter = "name", name = const.BUILDER } }
for name in pairs(const.MARKERS) do raised_filters[#raised_filters + 1] = { filter = "ghost_name", name = name } end
script.on_event(defines.events.script_raised_built, function(event)
  stamp.on_script_raised_built(event)
  builder.on_built(event)
end, raised_filters)
script.on_event(defines.events.on_entity_settings_pasted, builder.on_entity_settings_pasted)
script.on_event(defines.events.on_blueprint_settings_pasted, builder.on_blueprint_settings_pasted)
script.on_event(defines.events.on_object_destroyed, function(event)
  builder.on_object_destroyed(event)
  tracking.on_object_destroyed(event)
end)
script.on_event(defines.events.on_post_entity_died, tracking.on_post_entity_died)
script.on_event({ defines.events.on_robot_mined_entity, defines.events.on_player_mined_entity }, tracking.on_mined)
script.on_event(defines.events.on_player_setup_blueprint, tracking.on_player_setup_blueprint)

-- The area tool's outlines are drawn again after a drag: a right-drag
-- retires copies, a drag starts new ones.
local function redraw_outlines(event)
  local player = game.get_player(event.player_index)
  if player then outlines.cursor_changed(player) end
end

-- The area tool and the marker tools: each acts only on selections made with it.
local function on_selected(event)
  tool.on_selected(event)
  marker_tools.on_selected(event)
  redraw_outlines(event)
end
local function on_reverse_selected(event)
  tool.on_reverse_selected(event)
  marker_tools.on_reverse_selected(event)
  redraw_outlines(event)
end
script.on_event(defines.events.on_player_selected_area, on_selected)
script.on_event(defines.events.on_player_alt_selected_area, on_selected)
script.on_event(defines.events.on_player_reverse_selected_area, on_reverse_selected)
script.on_event(defines.events.on_player_alt_reverse_selected_area, on_reverse_selected)
script.on_event(defines.events.on_pre_build, tool.on_pre_build)

-- Window
local function toggle_for(event)
  local player = game.get_player(event.player_index)
  if player then window.toggle(player) end
end
script.on_event(defines.events.on_lua_shortcut, function(event)
  if event.prototype_name == const.TOGGLE then toggle_for(event) end
end)
script.on_event(const.TOGGLE, toggle_for)
script.on_event(defines.events.on_gui_click, actions.on_click)
script.on_event(defines.events.on_gui_checked_state_changed, actions.on_checked)
script.on_event(defines.events.on_gui_text_changed, actions.on_text_changed)
script.on_event(defines.events.on_gui_confirmed, actions.on_confirmed)
script.on_event(defines.events.on_gui_elem_changed, actions.on_elem_changed)
script.on_event(defines.events.on_gui_closed, function(event)
  local element = event.element
  local is_builder = element and element.valid and element.name == builder_view.NAME
  actions.on_closed(event)
  local player = game.get_player(event.player_index)
  if player and is_builder then builder_view.close(player) end
end)
-- A builder opens its own window instead of the decider combinator's.
script.on_event(defines.events.on_gui_opened, function(event)
  local entity = event.entity
  if not (entity and entity.valid and entity.name == const.BUILDER) then return end
  local player = game.get_player(event.player_index)
  if player then builder_view.open(player, entity) end
end)
script.on_event(defines.events.on_gui_location_changed, help_view.on_location_changed)
script.on_event(defines.events.on_gui_selected_tab_changed, help_view.on_tab_changed)
script.on_event(defines.events.on_gui_hover, actions.on_hover)
script.on_event(defines.events.on_gui_leave, actions.on_leave)
script.on_event(defines.events.on_player_cursor_stack_changed, function(event)
  local player = game.get_player(event.player_index)
  if not player then return end
  window.cursor_changed(player)
  outlines.cursor_changed(player)
end)

-- World lifecycle
script.on_event({ defines.events.on_surface_deleted, defines.events.on_surface_cleared }, function(event)
  lifecycle.drop_surface(event.surface_index)
end)
script.on_event(defines.events.on_forces_merged, function(event)
  lifecycle.drop_force(event.source_index)
end)
-- A map setting a player changed: what waited on the old value looks again.
script.on_event(defines.events.on_runtime_mod_setting_changed, limit_changes.on_setting_changed)
script.on_event(defines.events.on_player_changed_force, function(event)
  local player = game.get_player(event.player_index)
  if not player then return end
  window.close(player)
  tool.forget(player)
end)
script.on_event(defines.events.on_force_created, labs.on_force_created)
-- A window stays open across a disconnect, and rows only redraw for players
-- who are connected: draw it afresh on return.
-- Pictures and the window's height are sized for the screen at draw time.
script.on_event({ defines.events.on_player_display_scale_changed, defines.events.on_player_display_resolution_changed },
  function(event)
    local player = game.get_player(event.player_index)
    if not player then return end
    window.refresh(player)
    help_view.refresh(player)
  end)
script.on_event(defines.events.on_player_joined_game, function(event)
  local player = game.get_player(event.player_index)
  if player then window.refresh(player) end
end)
script.on_event(defines.events.on_chunk_generated, loop.on_chunk_generated)
script.on_event(defines.events.on_resource_depleted, depletion.on_resource_depleted)
script.on_event(defines.events.on_research_finished, research.on_research_finished)
script.on_event(defines.events.on_player_removed, function(event)
  registry.drop_player(event.player_index)
end)
