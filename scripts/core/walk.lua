-- A socket's designs tried in turn (a pool's, or its one design): the first
-- that is stamped, planned or held at a gate wins, and when none fits the
-- first one's reason closes the socket. Each design left behind is paid
-- for at once, and the walk stops before the next one when the force's
-- share is used up or the step has done about the work of checking one
-- design at the part cap. The socket then keeps where the walk got to
-- (socket.walk, in storage) and the next step goes on from there, so the
-- first design that fits still wins and none is tried twice at that spot.

local const = require("scripts.const")
local budget = require("scripts.core.budget")
local limits = require("scripts.core.limits")
local spots = require("scripts.core.spots")
local work = require("scripts.core.work")

local walk = {}

local REASON = const.REASON

-- The part cap's default, for a force without one: however long a pool,
-- its step is then no bigger than a step of one big design.
local UNCAPPED_PARTS = 5000

local function ceiling(force_index)
  local cap = limits.of(force_index, "design_parts")
  if cap == 0 then cap = UNCAPPED_PARTS end
  return cap * budget.COST.check_part
end

-- The walk stops before design `i`; the project waits its turn at the busy
-- gate, closing nothing.
local function pause(socket, state, i, checked)
  state.next, socket.walk = i, state
  return { kind = "gate", reason = REASON.busy, work = work.new(), checked = checked }
end

-- Design `i` was stamped, planned or held at a gate: it wins. A gate keeps
-- the walk at it, so the socket waits for that design.
local function won(socket, state, i, result, checked)
  socket.walk = nil
  if result.kind == "gate" and i > 1 then state.next, socket.walk = i, state end
  result.checked = checked
  return result
end

-- No design fits: the first one's reason closes the socket.
local function lost(socket, state, tally, checked)
  socket.walk = nil
  local first = state.first or { reason = REASON.unknown_design, position = socket.position }
  local result = spots.closed(first.reason, first.position)
  result.work, result.checked = tally, checked
  return result
end

-- try(project, socket, design) tries one design at the socket (growth.lua)
-- and gives its `work` and `checked`. Returns the step's result: its `work`
-- is the last design's, for the caller to charge, and `checked` counts
-- every design tried.
function walk.designs(project, socket, candidates, try)
  local state, force_index = socket.walk or { next = 1 }, project.force_index
  local most, spent, checked = ceiling(force_index), 0, 0
  for i = state.next, #candidates do
    if i > state.next and (spent >= most or not budget.ready(force_index)) then
      return pause(socket, state, i, checked)
    end
    local result = try(project, socket, candidates[i])
    checked = checked + result.checked
    if result.kind ~= "closed" then return won(socket, state, i, result, checked) end
    state.first = state.first or { reason = result.reason, position = result.position }
    -- A materials wait was that design's; the next one starts afresh.
    socket.waiting = nil
    if i == #candidates then return lost(socket, state, result.work, checked) end
    spent = spent + work.charge(force_index, result.work)
  end
  return lost(socket, state, work.new(), checked)
end

return walk
