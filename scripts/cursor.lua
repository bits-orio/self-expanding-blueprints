-- What a player is told at their cursor, what blueprint they hold, and
-- freeing the cursor for an item the mod hands out; shared by the window,
-- the grow tool and the markers.

local const = require("scripts.const")

local cursor = {}

function cursor.say(player, text)
  player.create_local_flying_text { text = text, create_at_cursor = true }
end

-- The blueprint or book in the cursor: a stack, or a record picked from the
-- blueprint library (planner records do not count).
function cursor.blueprint(player)
  local record = player.cursor_record
  if record then
    if record.type == "blueprint" or record.type == "blueprint-book" then return record end
    return nil
  end
  local stack = player.cursor_stack
  -- The design in hand while growing is no blueprint to add.
  if stack and stack.valid_for_read and stack.name == const.GROW_BLUEPRINT then return nil end
  if stack and stack.valid_for_read and (stack.is_blueprint or stack.is_blueprint_book) then return stack end
end

-- The player's emptied cursor stack, or nil after asking them to empty it.
function cursor.free(player)
  if not player.clear_cursor() then
    cursor.say(player, { "seb-message.cursor-full" })
    return nil
  end
  return player.cursor_stack
end

return cursor
