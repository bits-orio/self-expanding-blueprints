-- The marker tools. The window's Ore sensor and Keep clear buttons put one in
-- the cursor: a click puts its marker on the tile under it, a drag on every
-- tile of the rectangle, and a right-click or right-drag takes them off
-- again, one tile or many. Keep clear leaves tiles under the force's own
-- buildings and ghosts unmarked (they are the build); an ore sensor goes on
-- them too, since one on a drill watches the drill's whole mining area.

local const = require("scripts.const")
local cursor = require("scripts.cursor")

local marker_tools = {}

local MAX_MARKED = 4096     -- tiles one drag marks at most: 64 x 64
local MAX_CLEARED = 65536   -- tiles one right-drag takes marks off at most

-- Per tool: the marker it places, whether buildings' tiles are skipped, and
-- the messages it says (seb-message.<said>-marked and -removed).
local TOOLS = {
  [const.CLEAR_TOOL] = { marker = const.CLEAR, skip_built = true, said = "keep-clear" },
  [const.SENSOR_TOOL] = { marker = const.SENSOR, skip_built = false, said = "sensor" },
}

function marker_tools.give(player, name)
  if not TOOLS[name] then return false end
  local stack = cursor.free(player)
  if not stack then return false end
  return stack.set_stack { name = name }
end

-- The whole tiles a selection covers; a click covers the tile under it.
local function tiles_of(area)
  local left, top = math.floor(area.left_top.x), math.floor(area.left_top.y)
  return left, top, math.max(left + 1, math.ceil(area.right_bottom.x)), math.max(top + 1, math.ceil(area.right_bottom.y))
end

-- Whether the tile holds the tool's marker already or, for a tool that
-- skips them, a building or ghost of the force (anything not a marker).
local function taken(surface, force, x, y, tool)
  local area = { { x, y }, { x + 1, y + 1 } }
  for _, e in pairs(surface.find_entities_filtered { area = area, force = force }) do
    local name = e.type == "entity-ghost" and e.ghost_name or e.name
    if name == tool.marker or (tool.skip_built and not const.MARKERS[name]) then return true end
  end
  return false
end

local function mark(player, event, tool)
  local left, top, right, bottom = tiles_of(event.area)
  if (right - left) * (bottom - top) > MAX_MARKED then
    return cursor.say(player, { "seb-message.markers-too-big", MAX_MARKED })
  end
  local surface, force, count = event.surface, player.force, 0
  for x = left, right - 1 do
    for y = top, bottom - 1 do
      if not taken(surface, force, x, y, tool) then
        surface.create_entity { name = tool.marker, position = { x + 0.5, y + 0.5 }, force = force, player = player }
        count = count + 1
      end
    end
  end
  cursor.say(player, { "seb-message." .. tool.said .. "-marked", count })
end

local function unmark(player, event, tool)
  local left, top, right, bottom = tiles_of(event.area)
  if (right - left) * (bottom - top) > MAX_CLEARED then
    return cursor.say(player, { "seb-message.markers-too-big", MAX_CLEARED })
  end
  local count = 0
  local area = { { left, top }, { right, bottom } }
  for _, e in pairs(event.surface.find_entities_filtered { area = area, name = tool.marker, force = player.force }) do
    e.destroy()
    count = count + 1
  end
  cursor.say(player, { "seb-message." .. tool.said .. "-removed", count })
end

function marker_tools.on_selected(event)
  local tool = TOOLS[event.item]
  local player = tool and game.get_player(event.player_index)
  if player then mark(player, event, tool) end
end

function marker_tools.on_reverse_selected(event)
  local tool = TOOLS[event.item]
  local player = tool and game.get_player(event.player_index)
  if player then unmark(player, event, tool) end
end

return marker_tools
