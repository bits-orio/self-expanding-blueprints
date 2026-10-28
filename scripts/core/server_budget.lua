-- The whole server's time for the mod's work (seb-work-per-tick, DESIGN.md
-- D44): one account for every team together, charged beside each team's
-- own (budget.lua). The work runs on the runs of the due-tick queue, every
-- few ticks (scheduler.lua), so the account holds one run's worth and
-- refills at the rate per tick: over time the server does about the rate,
-- and a run at most a run's worth plus the piece that empties the account.
-- A charge takes only what is there, so the server is never in debt: a
-- team's big piece is its own team's debt, and the others wait at most for
-- the next run.
--   The teams take the account in turns, as in fair queueing, by the
-- server time each has had (`used`):
--   - a team the account refused waits, and while it does no other team
--     goes more than a turn (half a run's worth) ahead of it, so it is
--     served before the teams that had their turn;
--   - a team that starts asking again counts as at most a turn behind where
--     the newest piece started (`clock`): time it did not ask for is not
--     saved up against the others;
--   - what a team took in the run before, when that was all it asked for,
--     is kept for it in this run until it asks (a turn at most), so a team
--     that needs little gets it every run, wherever it comes in the run.
-- storage.server_budget = {level, tick, clock, refused, teams = {[force
-- index] = team record (below)}}, made on first use.

local limits = require("scripts.core.limits")
local scheduler = require("scripts.core.scheduler")

local server_budget = {}

-- A refused team asks again by the next run (budget.wait), or a builder's
-- request by its next read, 12 ticks on; one that has not by then holds no
-- one back.
local WAIT_KEPT = 12

local function account(rate, now)
  local cap = rate * scheduler.INTERVAL
  local a = storage.server_budget
  if not a then
    a = { level = cap, tick = now, clock = 0, teams = {} }
    storage.server_budget = a
  end
  a.level = math.min(cap, a.level + (now - a.tick) * rate)
  a.tick = now
  return a
end

-- A team's record: `used`; `refused`, when the account last refused it (nil
-- once it was let go since); `served`, when it was last let go; `took`, what
-- it was charged in the run at `took_tick`, its latest; `piece`, its last
-- charge.
local function team(a, force_index)
  local t = a.teams[force_index]
  if not t then
    t = { used = 0, took = 0, piece = 0 }
    a.teams[force_index] = t
  end
  return t
end

local function recent(a, tick)
  return tick ~= nil and a.tick - tick <= WAIT_KEPT
end

-- Of the teams other than `force_index`: the least `used` of those that
-- wait, and what is kept for those that got all they asked for in the run
-- before and have not asked in this one.
local function others(a, force_index, turn)
  local least, keep = nil, 0
  local before = a.tick - scheduler.INTERVAL
  for index, t in pairs(a.teams) do
    if index ~= force_index then
      if recent(a, t.refused) then
        least = math.min(least or t.used, t.used)
      elseif t.took_tick == before and (t.served or 0) < a.tick then
        keep = keep + math.min(t.took, turn)
      end
    end
  end
  return least, keep
end

-- Whether team `t` may go now. While no team has been refused lately there
-- are no turns to keep. A piece like its last one must leave what is kept
-- for the others, counting a turn of each at most, so a piece bigger than
-- that still goes from a full account.
local function may_go(a, force_index, t, turn)
  if a.level <= 0 then return false end
  if not recent(a, a.refused) then return true end
  local least, keep = others(a, force_index, turn)
  if keep > 0 and a.level - math.min(t.piece, turn) < math.min(keep, turn) then return false end
  return least == nil or t.used < least + turn
end

-- Whether the server lets the force start more work now.
function server_budget.ready(force_index)
  local rate = limits.server("work")
  if rate == 0 then return true end
  local a = account(rate, game.tick)
  local turn = rate * scheduler.INTERVAL / 2
  local t = team(a, force_index)
  if not recent(a, t.refused) and (t.served or 0) < a.tick then
    t.used = math.max(t.used, a.clock - turn)
  end
  if may_go(a, force_index, t, turn) then
    t.served, t.refused = a.tick, nil
    return true
  end
  t.refused, a.refused = a.tick, a.tick
  return false
end

-- Charges `cost` microseconds of the force's work to the server.
function server_budget.charge(force_index, cost)
  local rate = limits.server("work")
  if rate == 0 then return end
  local a = account(rate, game.tick)
  local t = team(a, force_index)
  a.clock = math.max(a.clock, t.used)
  if t.took_tick ~= a.tick then t.took, t.took_tick = 0, a.tick end
  t.used, t.took, t.piece = t.used + cost, t.took + cost, cost
  a.level = math.max(0, a.level - cost)
end

-- A force merged or released: a new force may get its index.
function server_budget.drop_force(force_index)
  local a = storage.server_budget
  if a then a.teams[force_index] = nil end
end

return server_budget
