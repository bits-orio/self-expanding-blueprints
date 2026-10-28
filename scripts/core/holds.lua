-- What holds a project's next socket without closing it, and what wakes the
-- project again (ADR-0011): a materials or robots wait retries on a timer,
-- since items arriving in a network raise no event; a wait for the map
-- ends when its chunk is generated; a wait for the force's share of server
-- time ends with the project's turn in its force's line (pace.lua). The
-- capacity gate is woken by a copy settling (loop.wake_force). A wait goes
-- into the history once, when it starts or its item changes; the next stamp
-- ends it (loop.lua).

local const = require("scripts.const")
local scheduler = require("scripts.core.scheduler")
local history = require("scripts.core.history")
local events = require("scripts.remote.events")
local pace = require("scripts.core.pace")

local holds = {}

local REASON = const.REASON

-- The project advances `delay` ticks from now (one at least); an advance
-- already queued sooner stands.
function holds.queue_advance(project, delay)
  local tick = game.tick + math.max(delay or 1, 1)
  if project.advance_tick and project.advance_tick <= tick then return end
  project.advance_tick = tick
  scheduler.at(tick, { kind = "advance", id = project.id })
end

-- Raised on entering the missing-materials gate or when its item changes,
-- not on every retry.
local function raise_missing(project, item)
  local key = item and item.name or ""
  if project.missing_raised == key then return end
  project.missing_raised = key
  script.raise_event(events.on_materials_missing, {
    project_id = project.id, item = item and item.name, count = item and item.count,
  })
end

local function log_wait(project, result)
  local item = result.item
  local key = result.reason .. "|" .. (item and item.name or "")
  if project.waiting_logged == key then return end
  project.waiting_logged = key
  history.add(project, { kind = "waiting", reason = result.reason, item = item and item.name, item_count = item and item.count })
end

-- The force has used up its share of server time for now: the project
-- waits in the force's line without closing anything, and has its turn
-- when the share is there again. The wait goes into the history once: it
-- lasts until the project has nothing left to try or another gate holds it.
function holds.wait_busy(project)
  project.gate = { reason = REASON.busy }
  if not project.busy_logged then
    project.busy_logged = true
    history.add(project, { kind = "waiting", reason = REASON.busy })
  end
  pace.join(project)
end

-- A gate holds the project at the socket it tried. A step that ran out of
-- its force's share midway (a pool tried a few designs at a time) keeps
-- the socket and waits its turn like a step that never started.
function holds.hold(project, result)
  if result.reason == REASON.busy then return holds.wait_busy(project) end
  project.gate = { reason = result.reason, item = result.item }
  project.busy_logged = nil
  log_wait(project, result)
  if result.reason == REASON.chunks then
    local waiting = storage.chunk_waits[project.surface_index] or {}
    waiting[project.id] = true
    storage.chunk_waits[project.surface_index] = waiting
    return
  end
  if result.reason == REASON.missing_materials then raise_missing(project, result.item) end
  holds.queue_advance(project, const.MATERIALS_RETRY)
end

-- A chunk came into being on a surface where projects wait for the map:
-- each tries again (and waits again if its chunks are not all there yet).
function holds.on_chunk_generated(event)
  local waiting = storage.chunk_waits[event.surface.index]
  if not waiting then return end
  storage.chunk_waits[event.surface.index] = nil
  for id in pairs(waiting) do
    local project = storage.projects[id]
    if project then holds.queue_advance(project, 1) end
  end
end

return holds
