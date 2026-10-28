-- A project's history: the last few things worth telling a player about it,
-- oldest first. Entries are plain data ({tick, kind, count, ...}) that the
-- window renders and the remote interface hands out as they are. Routine
-- progress is not history (the counts show it); waits, blocks, stalls,
-- pauses and the finish are.

local history = {}

local KEEP = 10

-- Kinds:
--   started {position}             waiting {reason, item, item_count}
--   blocked {reason, position}     unreachable {position}
--   stalled {instance_id, reason}  incomplete {instance_id}
--   paused, resumed {player_index} finished {copies}
--   waiting-ore, ore-gone, depleted {instance_id}   (ore sensors, retirement)
--   updated {copies, refused, player_index}         built-plan {player_index}
--   replaced {limit}   a plan stopped for a newer one (the force keeps
--                      `limit` live plans, retention.lua)
-- A repeat of the newest entry (same kind, reason and item) takes the new
-- entry's details and counts up, so a lake closing forty sockets is one line,
-- "Blocked by water (x40)", at the last place and tick.
local function same(a, b)
  return a.kind == b.kind and a.reason == b.reason and a.item == b.item
end

function history.add(project, entry)
  local list = project.history or {}
  project.history = list
  entry.tick = game.tick
  local last = list[#list]
  if last and same(last, entry) then
    local count = last.count + 1
    for k, v in pairs(entry) do last[k] = v end
    last.count = count
    return
  end
  entry.count = 1
  list[#list + 1] = entry
  if #list > KEEP then table.remove(list, 1) end
end

-- A copy for the remote interface, newest last.
function history.copy(project)
  local out = {}
  for i, entry in ipairs(project.history or {}) do
    local e = {}
    for k, v in pairs(entry) do e[k] = v end
    out[i] = e
  end
  return out
end

return history
