-- The growth loop: one project's advance. A project holds a frontier of
-- open sockets (frontier.lua), tried breadth-first by default. Sockets open
-- when their instance completes, so growth runs exactly as fast as the
-- robots. A gate holds the next socket until a completion (capacity), a
-- retry timer, the map or the force's turn reopens it (holds.lua); a socket
-- no robots reach is parked on its own and retried slowly, and one whose
-- copy would stand on its parent, going for depletion, waits on its own
-- until the parent is gone, so neither blocks the rest.

local const = require("scripts.const")
local scheduler = require("scripts.core.scheduler")
local gates = require("scripts.core.gates")
local growth = require("scripts.core.growth")
local work = require("scripts.core.work")
local frontier = require("scripts.core.frontier")
local history = require("scripts.core.history")
local plan = require("scripts.core.plan")
local previews = require("scripts.core.previews")
local overlay = require("scripts.render.overlay")
local events = require("scripts.remote.events")
local registry = require("scripts.core.registry")
local pace = require("scripts.core.pace")
local holds = require("scripts.core.holds")
local retry = require("scripts.core.retry")

local loop = {}

-- changed(project): set by projects.lua so open windows refresh.
-- ended(project): a real project finished, set by projects.lua (retention).
-- nothing_built(project): it finished without a copy, set by tool.lua; called
-- last, once the rest is done with the project, as it may forget it.
loop.hooks = {}

local STATE = const.PROJECT_STATE
local REASON = const.REASON
-- Closes worth a mark on the map and a line in the history; the rest
-- (joined, area edge, count) are the normal shape of growth and are only
-- counted, a count reached once in the history (close_rest).
local MARKED = {
  [REASON.water] = true, [REASON.cliff] = true, [REASON.building] = true, [REASON.uncharted] = true,
  [REASON.unknown_design] = true, [REASON.invalid_design] = true, [REASON.stamp_short] = true,
  [REASON.overlaps_parent] = true, [REASON.no_resource] = true, [REASON.off_grid] = true,
  [REASON.misaligned] = true, [REASON.probe] = true, [REASON.held_land] = true, [REASON.enemies] = true,
}
loop.MARKED = MARKED

-- Every module that wakes a project calls these through the loop.
loop.queue_advance = holds.queue_advance
loop.on_chunk_generated = holds.on_chunk_generated

local function changed(project)
  if loop.hooks.changed then loop.hooks.changed(project) end
end

-- A slot under the map's per-force cap came free: every project of the
-- force held at the capacity gate tries again (its own copies finishing is
-- not the only thing that frees one). With no cap left (0) a project held
-- under the old one is woken too.
function loop.wake_force(force_index)
  for id in pairs(registry.project_ids(force_index)) do
    local project = storage.projects[id]
    local gate = project and project.gate
    if gate and gate.reason == REASON.capacity and project.state == STATE.growing then loop.queue_advance(project, 1) end
  end
end

local function record_close(project, socket, result)
  project.closed[result.reason] = (project.closed[result.reason] or 0) + 1
  if not MARKED[result.reason] then return end
  local position = result.position or socket.position
  local blocked = project.blocked
  local entry = { position = position, reason = result.reason }
  blocked[#blocked + 1] = entry
  retry.keep(project, socket, entry)
  if #blocked > const.MAX_BLOCKED_KEPT then table.remove(blocked, 1) end
  history.add(project, { kind = "blocked", reason = result.reason, position = position })
  if project.gates.notify then
    script.raise_event(events.on_instance_blocked, { project_id = project.id, reason = result.reason, position = position })
  end
end

-- Past its count (max_instances, or plan.LIMIT for a plan) no socket of the
-- project can ever stamp: the rest close with this one in one pass, the
-- parked ones too, and the history says so once.
local function close_rest(project, socket)
  local closed = project.closed
  if not closed[REASON.count_reached] then
    history.add(project, { kind = "blocked", reason = REASON.count_reached, position = socket.position })
  end
  closed[REASON.count_reached] = (closed[REASON.count_reached] or 0) + 1 + frontier.pending(project)
  frontier.clear(project)
end

local function record_stamp(project, instance)
  project.count = project.count + 1
  project.building = project.building + 1
  project.instance_ids[instance.id] = true
  project.oldest_version = math.min(project.oldest_version or instance.version, instance.version)
  project.missing_raised, project.waiting_logged = nil, nil
end

-- A project that ended before building anything keeps why (its commonest
-- closing, joined included) and where it began, for its row and a line to
-- whoever started it.
local function nothing_built(project)
  local best, most = nil, 0
  for reason, n in pairs(project.closed) do
    if n > most then best, most = reason, n end
  end
  project.nothing_built = { reason = best, position = project.seed_position }
end

-- Done when nothing is open, building, or waiting for its ore to run out.
-- Returns true when it finished now.
local function maybe_finish(project)
  if project.state ~= STATE.growing or frontier.pending(project) > 0 or project.building > 0 then return false end
  if next(project.waiting_ore or {}) then return false end
  project.state = STATE.finished
  project.gate = nil
  history.add(project, { kind = "finished", copies = project.count })
  if project.count == 0 then nothing_built(project) end
  script.raise_event(events.on_project_finished, { project_id = project.id, count = project.count })
  return true
end

-- What the overlay and the window show of a project parked at a gate; a retry
-- that pops nothing and leaves this unchanged has nothing new to draw.
local function parked_key(project)
  local gate = project.gate
  if not gate then return nil end
  local item = gate.item
  return table.concat({ gate.reason, item and item.name or "", item and item.have or "", #project.frontier,
    #project.parked, #(project.awaiting or {}), project.count, project.building, #project.blocked }, "|")
end

-- A socket no robots reach is parked on its own; the first time it is, the
-- history says where.
local function park(project, socket)
  if not socket.unreachable then
    socket.unreachable = true
    history.add(project, { kind = "unreachable", position = socket.position })
  end
  frontier.park(project, socket)
end

-- A copy stamped: counted now, so the overlay draws where it grows next
-- and drops the marks of copies whose next copy the count just ruled out.
-- A fast fill opens a copy's sockets the moment it is placed, unless it
-- must wait for its ore (copy_events.lua opens those).
local function stamped(project, result)
  local instance = result.instance
  record_stamp(project, instance)
  if project.open_early and #(instance.sensors or {}) == 0 then
    instance.opened_early = true
    frontier.open(project, instance)
  end
  overlay.refresh_instance(instance)
  if project.rules.max_instances and project.count >= project.rules.max_instances then
    overlay.refresh_pending(project)
  end
  return pace.units(growth.parts(result.spot.prepared))
end

-- A planned copy is finished the moment it is planned, and its outline is
-- drawn then, once. Its look-only ghosts are built like a stamp's, and
-- charged so.
local function planned(project, result)
  project.count = project.count + 1
  local copy = plan.add(project, result.spot)
  overlay.draw_planned(project, copy)
  local pasted = previews.paste(project, result.spot)
  pace.charge_ghosts(project, pasted, pasted > 0 and work.poles(result.spot.prepared) or 0)
  frontier.open(project, copy)
  -- Open now, its sockets are never read again: a plan of 400 copies that
  -- draw 64 sockets each would keep 25,600 of them in the save.
  copy.sockets = nil
  return pace.units(result.checked)
end

-- A closed socket costs a unit; a plan's costs by the parts it checked, as
-- a planned copy does (a real project's close is paced by its stamps).
local function close(project, socket, result)
  if result.reason == REASON.count_reached then
    close_rest(project, socket)
  else
    record_close(project, socket, result)
  end
  if project.dry_run and (result.checked or 0) > 0 then return pace.units(result.checked) end
  return 1
end

-- No robots reaching a socket is its own condition: it is parked, and the
-- rest go on. So is waiting for the copy it grows from to be removed: the
-- socket is set aside until that copy is gone (copy_events.lua). Any other
-- gate, a pool step stopped midway too, holds the project at this socket
-- (holds.lua).
local function gated(project, socket, result)
  if result.reason == REASON.parent_retiring then
    frontier.await(project, socket)
    return 1, false
  end
  if result.reason ~= REASON.no_network then return holds.hold(project, result) end
  park(project, socket)
  return 1, false
end

-- Tries the socket the project tries next. Returns the work it cost,
-- whether it left the frontier for good and whether it stamped; or nil
-- when a gate holds the frontier.
local function step(project, socket)
  local result = growth.try(project, socket)
  pace.charge(project, result)
  if result.kind == "gate" then return gated(project, socket, result) end
  frontier.take(project, socket)
  if result.kind == "stamped" then return stamped(project, result), true, true end
  if result.kind == "planned" then return planned(project, result), true end
  return close(project, socket, result), true
end

-- Steps through the frontier while the project has room for another copy,
-- work left in this run and its force a share of server time. The room is
-- counted once and down as it stamps. Returns whether a socket left.
local function run_steps(project)
  local work, popped, last = pace.WORK_BUDGET, false, 0
  local room = #project.frontier > 0 and gates.room(project) or 0
  while #project.frontier > 0 do
    if room <= 0 then project.gate = { reason = REASON.capacity } break end
    if work <= 0 or work < last then loop.queue_advance(project, 1) break end
    if not pace.ready(project) then holds.wait_busy(project) break end
    local cost, left, made = step(project, frontier.peek(project))
    if not cost then break end
    work, popped = work - cost, popped or left
    if made then room = room - 1 end
    if cost >= pace.STAMP_COST then last = cost end
  end
  if #project.frontier == 0 then project.busy_logged = nil end
  return popped
end

-- A project waiting in its force's line has its turn from there.
local function advance(project)
  if project.state ~= STATE.growing or pace.in_line(project) then return end
  project.gate = nil
  local popped = run_steps(project)
  local finished = maybe_finish(project)
  local key = not popped and parked_key(project) or nil
  if key and key == project.parked_key then return end
  project.parked_key = key
  overlay.refresh_project(project)
  changed(project)
  if finished and not project.dry_run and loop.hooks.ended then loop.hooks.ended(project) end
  if finished and project.count == 0 and loop.hooks.nothing_built then loop.hooks.nothing_built(project) end
end

pace.hooks.advance = advance

scheduler.register("advance", function(item, now)
  local project = storage.projects[item.id]
  if not project or (project.advance_tick and project.advance_tick > now) then return end
  project.advance_tick = nil
  advance(project)
end)

scheduler.register("unpark", function(item)
  local project = storage.projects[item.id]
  if not project or project.state == STATE.stopped then return end
  frontier.unpark(project)
  loop.queue_advance(project, 1)
end)

return loop
