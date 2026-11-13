-- Ctrl + Z after a click with a design in hand (or the area tool) takes the
-- project back: it stops, and every copy it placed is removed. Only
-- projects a player starts by hand are on an undo queue (undo_mark.lua);
-- ones a blueprint builder or another mod starts are nobody's to undo.

local removal = require("scripts.core.removal")
local undo_mark = require("scripts.core.undo_mark")
local cursor = require("scripts.cursor")

local undo = {}

-- A project of the player's team that started from a click.
function undo.note(player, project)
  undo_mark.note(player, project)
end

-- The engine keeps a redo item for the mark it removed; redoing it would
-- bring back a mark of no project, so it goes.
local function drop_redo(player)
  local stack = player.undo_redo_stack
  if stack.get_redo_item_count() > 0 then stack.remove_redo_item(1) end
end

local function take_back(player, project_id)
  local project = storage.projects[project_id]
  if not (project and project.force_index == player.force.index) then return end
  local removed = removal.stop(project, removal.ALL)
  cursor.say(player, { "seb-message.undone", removed })
end

function undo.on_undo_applied(event)
  local player = game.get_player(event.player_index)
  if not player then return end
  local ours = false
  for _, action in ipairs(event.actions) do
    local id = undo_mark.project_of(action)
    if id then
      ours = true
      take_back(player, id)
    end
  end
  if ours then drop_redo(player) end
end

return undo
