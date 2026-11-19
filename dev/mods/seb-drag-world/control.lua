-- A lab floor for dragging the area tool in multiplayer (dev/mp-drag.sh).
-- Every player who joins stands at the origin holding the area tool for a
-- solar-cell design, and gets it back when it leaves the hand. What the
-- mod's drag preview shows is logged as SEB_DRAG lines whenever it changes,
-- with the tick, by the server and by every client: the same lines on both
-- are the same simulation. The preview is read through the mod's test seam
-- (scripts/remote/test_seam.lua), which this mod's name opens.

local MOD = "self-expanding-blueprints"
local SEAM = MOD .. "-test"
local TOOL = "seb-grow-tool"

local CELL = {
  { entity_number = 1, name = "solar-panel", position = { x = 1.5, y = 1.5 } },
  { entity_number = 2, name = "solar-panel", position = { x = 4.5, y = 1.5 } },
  { entity_number = 3, name = "solar-panel", position = { x = 1.5, y = 4.5 } },
  { entity_number = 4, name = "solar-panel", position = { x = 4.5, y = 4.5 } },
  { entity_number = 5, name = "medium-electric-pole", position = { x = 6.5, y = 3.5 } },
}

local function say(text)
  log("SEB_DRAG t=" .. game.tick .. " " .. text)
end

local function floor(surface)
  surface.request_to_generate_chunks({ 0, 0 }, 4)
  surface.force_generate_chunk_requests()
  local tiles = {}
  for x = -100, 99 do
    for y = -100, 99 do tiles[#tiles + 1] = { name = "lab-dark-1", position = { x, y } } end
  end
  surface.set_tiles(tiles)
  for _, e in pairs(surface.find_entities_filtered { area = { { -100, -100 }, { 100, 100 } } }) do
    if e.type ~= "character" then e.destroy() end
  end
end

local function register_cell()
  local inventory = game.create_inventory(1)
  inventory[1].set_stack { name = "blueprint" }
  inventory[1].set_blueprint_entities(CELL)
  inventory[1].label = "Drag cell"
  local text = inventory[1].export_stack()
  inventory.destroy()
  return remote.call(MOD, "register_design", "player", text)
end

script.on_init(function()
  if remote.interfaces.freeplay then
    remote.call("freeplay", "set_skip_intro", true)
    remote.call("freeplay", "set_disable_crashsite", true)
  end
  local surface = game.surfaces.nauvis
  surface.always_day = true
  surface.show_clouds = false
  game.forces.enemy.kill_all_units()
  game.map_settings.enemy_expansion.enabled = false
  floor(surface)
  storage.design = register_cell()
  storage.placed, storage.shown = {}, {}
end)

local function list(indexes)
  return "{" .. table.concat(indexes, ",") .. "}"
end

-- One line for what the seam says the player's preview shows.
local function describe(shown)
  if not shown then return "none" end
  local words = {}
  for i, word in ipairs(shown.text) do words[i] = tostring(word) end
  return string.format("box=%.1f,%.1f,%.1f,%.1f %s text=%s box_players=%s text_players=%s",
    shown.left, shown.top, shown.right, shown.bottom, shown.green and "green" or "red",
    table.concat(words, ":"), list(shown.box_players), list(shown.text_players))
end

-- Logs the player's preview when it is not what was logged last, and fails
-- when anyone but that player would see it.
local function note(player_index)
  local shown = remote.call(SEAM, "preview", player_index)
  local line = describe(shown)
  if storage.shown[player_index] == line then return end
  storage.shown[player_index] = line
  say("preview p=" .. player_index .. " " .. line)
  if not shown then return end
  local only = list({ player_index })
  if list(shown.box_players) ~= only or list(shown.text_players) ~= only then
    say("FAIL the preview of player " .. player_index .. " is drawn for others too")
  end
end

local EVENTS = {
  "on_player_start_selected_area", "on_player_change_selected_area", "on_player_cancel_selected_area",
  "on_player_selected_area", "on_player_alt_selected_area", "on_player_reverse_selected_area",
  "on_player_alt_reverse_selected_area",
}

-- This mod depends on the mod under test, so its handlers run after that
-- mod's: the preview read here is the one the event left behind.
for _, name in ipairs(EVENTS) do
  script.on_event(defines.events[name], function(event)
    if event.item ~= TOOL then return end
    local a, b, c = event.area.left_top, event.area.right_bottom, event.cursor_position
    say(string.format("ev=%s p=%d area=%.2f,%.2f,%.2f,%.2f cur=%s", name, event.player_index, a.x, a.y, b.x, b.y,
      c and string.format("%.2f,%.2f", c.x, c.y) or "-"))
    note(event.player_index)
  end)
end

script.on_event(defines.events.on_player_cursor_stack_changed, function(event)
  local stack = game.get_player(event.player_index).cursor_stack
  say("ev=cursor p=" .. event.player_index .. " holds=" .. (stack and stack.valid_for_read and stack.name or "nothing"))
  note(event.player_index)
end)

script.on_event(defines.events.on_tick, function()
  for _, player in pairs(game.connected_players) do note(player.index) end
end)

-- The freeplay character comes a moment after the player, so the tool is
-- handed over from here; a player who put it away gets it again.
script.on_nth_tick(20, function()
  for _, player in pairs(game.connected_players) do
    local stack = player.cursor_stack
    if stack and not storage.placed[player.index] then
      storage.placed[player.index] = true
      player.teleport({ 0, 0 })
      player.zoom = 0.5
    end
    if stack and not stack.valid_for_read then
      local given = remote.call(SEAM, "hold_area_tool", player.index, storage.design)
      say("tool p=" .. player.index .. " given=" .. tostring(given))
    end
  end
end)
