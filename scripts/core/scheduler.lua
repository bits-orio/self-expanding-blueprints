-- The due-tick queue: the only periodic handler in the mod.
--
-- Work items are filed under the tick they fall due. The on_nth_tick handler
-- that drains them is registered only while the queue holds work, and
-- storage.queue_armed records that it is. on_load re-registers it from that
-- flag alone, so a client joining a running game computes the same handler
-- set as the server; a registration that is not a pure function of storage
-- gets multiplayer joins refused as a handler mismatch.

local scheduler = {}

local INTERVAL = 6
scheduler.INTERVAL = INTERVAL   -- the server's account holds one run's worth (server_budget.lua)

local handlers = {}

-- Kinds are registered at load time (module root scope), never stored.
function scheduler.register(kind, handler)
  handlers[kind] = handler
end

function scheduler.init_storage()
  storage.queue = storage.queue or {}
end

local function arm()
  script.on_nth_tick(INTERVAL, scheduler.run)
end

local function disarm()
  script.on_nth_tick(INTERVAL, nil)
end

-- Files `item` (a table with a `kind`) to run at or after `tick`.
function scheduler.at(tick, item)
  local bucket = storage.queue[tick]
  if not bucket then
    bucket = {}
    storage.queue[tick] = bucket
  end
  bucket[#bucket + 1] = item
  if not storage.queue_min or tick < storage.queue_min then storage.queue_min = tick end
  if not storage.queue_armed then
    storage.queue_armed = true
    arm()
  end
end

-- Removes and returns the due buckets in tick order, recomputing queue_min
-- from what stays queued (nil when nothing does).
local function take_due(now)
  local due_ticks, next_min = {}, nil
  for tick in pairs(storage.queue) do
    if tick <= now then
      due_ticks[#due_ticks + 1] = tick
    elseif not next_min or tick < next_min then
      next_min = tick
    end
  end
  table.sort(due_ticks)
  local buckets = {}
  for i, tick in ipairs(due_ticks) do
    buckets[i] = storage.queue[tick]
    storage.queue[tick] = nil
  end
  storage.queue_min = next_min
  return buckets
end

local function dispatch(item, now)
  local handler = handlers[item.kind]
  if handler then
    handler(item, now)
  else
    log("[self-expanding-blueprints] no handler for queued work: " .. tostring(item.kind))
  end
end

function scheduler.run(event)
  local now = event.tick
  local min = storage.queue_min
  if not min or now < min then return end
  for _, bucket in ipairs(take_due(now)) do
    for _, item in ipairs(bucket) do dispatch(item, now) end
  end
  -- Handlers may have queued more work; only an empty queue disarms.
  if next(storage.queue) == nil then
    storage.queue_armed = nil
    storage.queue_min = nil
    disarm()
  end
end

function scheduler.on_load()
  if storage.queue_armed then arm() end
end

return scheduler
