-- Which blueprint builders of a team take requests (limits "builders",
-- D45): the ones placed first, up to the map's limit. The others wait
-- (b.waiting), showing the limit error on their output; when a working one
-- goes, the oldest waiting one takes its place. A raised limit lets waiting
-- builders in at once when set_limits, clear_limits or the map setting says
-- so (limit_changes.lua), else at the builders timer's next run, which
-- notices a script's change (builder.lua); a lowered one sends working
-- builders over it to wait, each once it has finished its request.
-- Three roots move only through add, work, wait and unwait below, so
-- they always match storage.builders:
--   storage.builders_working[force_index]  how many are working
--   storage.builders_waiting[force_index]  the waiting ones' ids, oldest first
--   storage.builders_active[id]            the working ones: the only
--                                          builders the timer looks at
-- They are made on first use (ensure), not in registry.init_storage: that
-- a save has none is how ensure knows it must count its builders afresh.

local limits = require("scripts.core.limits")

local roster = {}

-- waiting(b): set by builder.lua, which makes a builder that starts to wait
-- (a new one over the limit, one sent back, one counted afresh from an older
-- save) show the limit error.
roster.hooks = {}

local function add(force_index, n)
  local working = storage.builders_working
  local count = (working[force_index] or 0) + n
  working[force_index] = count > 0 and count or nil
end

local function count(force_index)
  return storage.builders_working[force_index] or 0
end

local function room(force_index)
  return not limits.reached(force_index, "builders", count(force_index))
end

-- Where `id` is, or would go, in a list of ids in ascending order.
local function position(list, id)
  local lo, hi = 1, #list + 1
  while lo < hi do
    local mid = math.floor((lo + hi) / 2)
    if list[mid] < id then lo = mid + 1 else hi = mid end
  end
  return lo
end

local function wait(b)
  b.waiting = true
  storage.builders_active[b.id] = nil
  local list = storage.builders_waiting[b.force_index] or {}
  storage.builders_waiting[b.force_index] = list
  table.insert(list, position(list, b.id), b.id)
  if roster.hooks.waiting then roster.hooks.waiting(b) end
end

-- Out of its force's waiting list (it may not be in it: an old save's
-- builder whose entity was gone was never listed).
local function unwait(b)
  local list = storage.builders_waiting[b.force_index]
  if not list then return end
  local i = position(list, b.id)
  if list[i] == b.id then table.remove(list, i) end
  if #list == 0 then storage.builders_waiting[b.force_index] = nil end
end

local function work(b)
  b.waiting = nil
  storage.builders_active[b.id] = true
  add(b.force_index, 1)
end

local function admit(b)
  if room(b.force_index) then work(b) else wait(b) end
end

-- Builders from a save made before the limit are counted afresh, in the
-- order they were placed; a save that has the count but not the lists
-- (the roster before they existed) gets them from its builders' flags.
-- Called before anything reads or changes them, while storage.builders
-- still holds every builder counted.
function roster.ensure()
  if storage.builders_working and storage.builders_waiting and storage.builders_active then return end
  local counted = storage.builders_working ~= nil
  storage.builders_working = storage.builders_working or {}
  storage.builders_waiting, storage.builders_active = {}, {}
  local ids = {}
  for id in pairs(storage.builders) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local b = storage.builders[id]
    if counted then
      if not b.waiting then storage.builders_active[id] = true elseif b.entity.valid then wait(b) end
    elseif not b.entity.valid then
      -- Never counted: its removal must not uncount it.
      b.waiting = true
    else
      b.force_index, b.surface_index = b.entity.force_index, b.entity.surface_index
      admit(b)
    end
  end
end

-- A new builder (or one that changed force): working if there is room.
function roster.join(b)
  admit(b)
end

-- The first `n` ids of the force's waiting list go in one move, so lifting
-- the limit for thousands of builders is one pass, not one per builder.
local function drop_front(force_index, list, n)
  local size = #list
  for i = n + 1, size do list[i - n] = list[i] end
  for i = size - n + 1, size do list[i] = nil end
  if size == n then storage.builders_waiting[force_index] = nil end
end

-- The oldest waiting builders of the force take the places that are free;
-- each is looked at at the builder timer's next run (next_read cleared).
-- Returns whether any was let in.
function roster.rebalance(force_index)
  local list, let_in, taken = storage.builders_waiting[force_index], false, 0
  while list and taken < #list and room(force_index) do
    taken = taken + 1
    local b = storage.builders[list[taken]]
    if b and b.waiting and b.force_index == force_index and b.entity.valid then
      work(b)
      b.next_read = nil
      let_in = true
    end
  end
  if taken > 0 then drop_front(force_index, list, taken) end
  return let_in
end

-- Every force's waiting builders, after a map setting changed.
function roster.rebalance_all()
  local let_in = false
  for force_index in pairs(storage.builders_waiting) do
    if roster.rebalance(force_index) then let_in = true end
  end
  return let_in
end

-- A builder that goes (already out of storage.builders) or changes force.
-- `dropping`: its whole force is going, so nobody takes its place and the
-- force's list is cleared once (forget_force).
function roster.leave(b, dropping)
  if b.waiting then
    if not dropping then unwait(b) end
    return
  end
  storage.builders_active[b.id] = nil
  add(b.force_index, -1)
  if not dropping then roster.rebalance(b.force_index) end
end

-- The force is merged or released: every builder of it has left.
function roster.forget_force(force_index)
  storage.builders_waiting[force_index] = nil
end

-- After builders left in a batch (`dropping`): the force's waiting list
-- keeps only the ones still waiting, in order.
function roster.compact(force_index)
  local list = storage.builders_waiting[force_index]
  if not list then return end
  local kept = {}
  for _, id in ipairs(list) do
    local b = storage.builders[id]
    if b and b.waiting and b.force_index == force_index then kept[#kept + 1] = id end
  end
  storage.builders_waiting[force_index] = #kept > 0 and kept or nil
end

-- At each look at a working builder between requests: it gives its place
-- up while its force is over a lowered limit. Returns whether the builder
-- waits (a waiting builder is no longer looked at, but a builder moved
-- into a full force may come here once).
function roster.waits(b, busy)
  if not b.waiting and not busy and limits.reached(b.force_index, "builders", count(b.force_index) - 1) then
    add(b.force_index, -1)
    b.answer = {}
    wait(b)
  end
  return b.waiting == true
end

function roster.limit(b)
  return limits.of(b.force_index, "builders")
end

return roster
