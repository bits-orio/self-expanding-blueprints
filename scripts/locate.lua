-- Shows a player where a project is. A project moves as it grows, so the
-- place is worked out at each click and never stored: a left click goes to
-- where it grows now (its copies under construction, else the socket it
-- tries next, else the sockets no robots reach), a right click to the whole
-- field. A finished project has none of those and shows its field. Remote
-- view centres there, zoomed to fit, and an outline only that player sees
-- blinks around it for a few seconds; the overlay already draws the front
-- live, so the player can watch it move from there.

local const = require("scripts.const")
local geometry = require("scripts.core.geometry")
local instances = require("scripts.core.instances")
local frontier = require("scripts.core.frontier")

local locate = {}

local SHOW_TICKS = 300
local BLINK_TICKS = 30
local MARGIN = 6          -- tiles kept around what is shown
local SOCKET_REACH = 3    -- half the size of the box around an open socket
local MIN_ZOOM, MAX_ZOOM = 0.05, 1
local COLOR = { r = 1, g = 0.85, b = 0.2, a = 1 }
local TILE_PIXELS = 32    -- a tile on screen at zoom 1

-- Controllers whose view a script may move into remote view.
local MOVABLE = {
  [defines.controllers.character] = true, [defines.controllers.god] = true,
  [defines.controllers.remote] = true, [defines.controllers.spectator] = true,
}

local function around(p, reach)
  return geometry.box(p.x - reach, p.y - reach, p.x + reach, p.y + reach)
end

local function sockets_box(sockets)
  local box
  for _, socket in ipairs(sockets) do box = geometry.union(box, around(socket.position, SOCKET_REACH)) end
  return box
end

-- Every copy of the project that passes `keep`.
local function copies(project, keep)
  local box
  for id in pairs(project.instance_ids) do
    local instance = storage.instances[id]
    if instance and keep(instance) then box = geometry.union(box, instance.footprint) end
  end
  return box
end

local function standing(instance)
  return instance.state ~= const.STATE.retired
end

-- Where it grows now. Not every open socket: a fill's frontier is a diagonal
-- across the whole field, so its box would be the field again.
local function now(project)
  return copies(project, instances.is_building)
    or sockets_box({ project.frontier[frontier.next_index(project) or 1] })
    or sockets_box(project.parked)
end

local function field(project)
  return geometry.union(copies(project, standing),
    geometry.union(sockets_box(project.frontier), sockets_box(project.parked)))
end

local function zoom_to_fit(player, box)
  local res = player.display_resolution
  local w, h = box.right - box.left + 2 * MARGIN, box.bottom - box.top + 2 * MARGIN
  local fit = math.min(res.width / (w * TILE_PIXELS), res.height / (h * TILE_PIXELS))
  player.zoom = math.max(MIN_ZOOM, math.min(MAX_ZOOM, fit))
end

-- Drawn for the map as well, since zooming out far enough switches remote
-- view to the map.
local function outline(player, surface, box)
  for _, mode in ipairs({ "game", "chart" }) do
    rendering.draw_rectangle {
      color = COLOR, width = 4, filled = false, surface = surface, players = { player },
      left_top = { box.left - 1, box.top - 1 }, right_bottom = { box.right + 1, box.bottom + 1 },
      render_mode = mode, time_to_live = SHOW_TICKS, blink_interval = BLINK_TICKS,
    }
  end
end

-- Shows one copy: remote view on its footprint, outlined for a moment.
function locate.instance(player, instance)
  local surface = game.surfaces[instance.surface_index]
  if not surface then return false end
  local box = instance.footprint
  outline(player, surface, box)
  if not MOVABLE[player.controller_type] then return true end
  player.set_controller { type = defines.controllers.remote, position = geometry.box_center(box), surface = surface }
  zoom_to_fit(player, box)
  return true
end

-- Returns false when nothing of the project is on the map. A player whose
-- view cannot move (map editor, cutscene) gets a map tag in chat instead.
function locate.project(player, project, whole)
  local surface = game.surfaces[project.surface_index]
  if not surface then return false end
  local box = (not whole and now(project)) or field(project)
  if not box then return false end
  local centre = geometry.box_center(box)
  outline(player, surface, box)
  if not MOVABLE[player.controller_type] then
    player.print({ "seb-message.project-location", project.id,
      string.format("[gps=%d,%d,%s]", math.floor(centre.x), math.floor(centre.y), surface.name) })
    return true
  end
  player.set_controller { type = defines.controllers.remote, position = centre, surface = surface }
  zoom_to_fit(player, box)
  return true
end

return locate
