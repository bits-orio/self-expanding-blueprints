-- Why a project is where it is, as data: the window words and colours it,
-- get_project hands it out. One level per project:
--   growing   copies are being placed or built (some spots may be out of
--             robot reach: `unreachable` counts them)
--   waiting   a gate holds it (materials, map generation, its team's share
--             of server time), or nothing is building and every spot left
--             is out of robot reach, or spots wait for the copy they grow
--             from to be removed, or every copy left waits for its ore to
--             run out (`count` of each)
--   stalled   a copy in flight has made no progress for a while
--   paused, finished, stopped
--   planning, planned   a dry run laying out its plan (with the `reason`
--             it waits, its team's share of server time), or done (`count`
--             copies)
-- Holding at the capacity gate is how a growing project paces itself, not
-- a wait, and a wait for the team's share is no stall.

local const = require("scripts.const")

local status = {}

local STATE = const.PROJECT_STATE
local REASON = const.REASON

-- The reason most of its stalled copies give, and how many are stalled.
local function stall(project)
  local tally, best, most, n = {}, nil, 0, 0
  for _, reason in pairs(project.stalled or {}) do
    n = n + 1
    tally[reason] = (tally[reason] or 0) + 1
    if tally[reason] > most then best, most = reason, tally[reason] end
  end
  return best, n
end

-- The commonest close worth naming: joining another copy is how a fill ends.
local function main_close(project)
  local best, most = nil, 0
  for reason, n in pairs(project.closed) do
    if n > most and reason ~= REASON.joined then best, most = reason, n end
  end
  return best, most
end

function status.of(project)
  local state = project.state
  if state == STATE.paused or state == STATE.stopped then return { level = state } end
  if project.dry_run then
    if state == STATE.finished then return { level = "planned", count = project.count } end
    return { level = "planning", count = project.count, reason = project.gate and project.gate.reason }
  end
  if state == STATE.finished then
    local reason, n = main_close(project)
    return { level = "finished", reason = reason, count = n }
  end
  local reason, stalled = stall(project)
  if reason then return { level = "stalled", reason = reason, count = stalled } end
  local gate = project.gate
  if gate and gate.reason ~= REASON.capacity then
    return { level = "waiting", reason = gate.reason, item = gate.item, network = gate.network }
  end
  local unreachable = #project.parked
  local idle = #project.frontier == 0 and project.building == 0
  if unreachable > 0 and idle then return { level = "waiting", reason = REASON.no_network, count = unreachable } end
  -- Asked before the ore: copies waiting for their ore may wait on these
  -- spots (the copy laid where a miner stood may power the next miner).
  local awaiting = #(project.awaiting or {})
  if awaiting > 0 and idle then return { level = "waiting", reason = REASON.parent_retiring, count = awaiting } end
  local ore = table_size(project.waiting_ore or {})
  if ore > 0 and idle then return { level = "waiting", reason = REASON.ore_left, count = ore } end
  return { level = "growing", unreachable = unreachable, ore = ore }
end

return status
