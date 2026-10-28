-- Marker arrows in the player's hands. Markers are drawn into designs; a
-- stamp destroys their ghosts itself (stamp.lua). Here: handing out marker
-- items, keeping the cursor stocked while drawing, and placing for real the
-- marker ghosts a player pastes with an ordinary blueprint, which robots
-- could never build (marker items exist only in the cursor): a design pasted
-- by hand to change it comes with its markers, settings and all.

local const = require("scripts.const")
local ghosts = require("scripts.core.ghosts")
local cursor = require("scripts.cursor")

local markers = {}

local PLACEABLE = {
  [const.SOCKET] = true, [const.ENTRY] = true, [const.SENSOR] = true, [const.PROBE] = true, [const.PORT] = true,
}
local HANDFUL = 20

function markers.give(player, item)
  if not PLACEABLE[item] then return false end
  local stack = cursor.free(player)
  if not stack then return false end
  return stack.set_stack { name = item, count = HANDFUL }
end

function markers.on_built_entity(event)
  local entity = event.entity
  if not (entity and entity.valid) then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  if ghosts.is_marker(entity) then
    -- Placed one by one (remote view, ghost cursor) they are part of a
    -- design being drawn and stay ghosts; pasted with a blueprint they are
    -- placed. The anchor is the mod's own and never belongs on the map.
    if not player.is_cursor_blueprint() then return end
    if entity.ghost_name == const.ANCHOR or not entity.revive() then entity.destroy() end
    return
  end
  if PLACEABLE[entity.name] then
    local stack = player.cursor_stack
    if stack and not stack.valid_for_read then stack.set_stack { name = entity.name, count = HANDFUL } end
  end
end

return markers
