-- What puts a project a player started by hand on that player's undo
-- queue. The API adds an undo item only for an entity built for a player,
-- so each such project has a mark: a ghost of const.UNDO_MARK (nothing to
-- see or select) of the neutral force, where the project began, built for
-- the player as an undo item of its own that carries the project's id as a
-- tag. Ctrl + Z removes the ghost and on_undo_applied hands the tag back
-- (undo.lua). Measured on 2.1.23: an undo item whose ghost is gone does
-- nothing and stays in the queue, where it blocks every item under it, so
-- the mark stands as long as the project is on record and its item leaves
-- the queue with it (undo_mark.drop). Robots never build a neutral ghost.

local const = require("scripts.const")

local undo_mark = {}

undo_mark.TAG = "seb-project"

-- The item just added is the newest, with the mark as its one action.
local NEWEST, ONLY = 1, 1

-- Marks `project` as started by `player`'s click.
function undo_mark.note(player, project)
  local surface = game.surfaces[project.surface_index]
  local stack = player.undo_redo_stack
  local before = stack.get_undo_item_count()
  local ghost = surface.create_entity {
    name = "entity-ghost", inner_name = const.UNDO_MARK, position = project.seed_position, force = "neutral",
    player = player, undo_index = 0,
  }
  if not ghost then return end
  if stack.get_undo_item_count() <= before then return ghost.destroy() end
  stack.set_undo_tag(NEWEST, ONLY, undo_mark.TAG, project.id)
  project.undo = { ghost = ghost, player_index = player.index }
  storage.undo_marks = storage.undo_marks or {}
  storage.undo_marks[script.register_on_object_destroyed(ghost)] = project.id
end

-- Takes the project's item out of the player's undo queue.
local function drop_item(player_index, project_id)
  local player = game.get_player(player_index)
  if not player then return end
  local stack = player.undo_redo_stack
  for i = stack.get_undo_item_count(), 1, -1 do
    if stack.get_undo_tag(i, ONLY, undo_mark.TAG) == project_id then stack.remove_undo_item(i) end
  end
end

-- The project ends or is forgotten (retention.let_go): its mark and its
-- undo item go.
function undo_mark.drop(project)
  local note = project.undo
  if not note then return end
  project.undo = nil
  if note.ghost.valid then note.ghost.destroy() end
  drop_item(note.player_index, project.id)
end

-- A mark that left the map by anything but Ctrl + Z or its project's end
-- (another script, its surface deleted) takes its undo item with it.
function undo_mark.on_object_destroyed(event)
  local marks = storage.undo_marks
  local id = marks and marks[event.registration_number]
  if not id then return end
  marks[event.registration_number] = nil
  local project = storage.projects[id]
  if project and project.undo and not project.undo.ghost.valid then undo_mark.drop(project) end
end

-- The id of the project an undone action stood for, or nil.
function undo_mark.project_of(action)
  return action.tags and action.tags[undo_mark.TAG]
end

return undo_mark
