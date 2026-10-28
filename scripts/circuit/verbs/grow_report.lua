-- What a Grow shows on its builder's output besides the answer (grow.lua):
-- ghosts left, open sockets, blocked sockets, copies built, and the next
-- copy's bill of materials as item signals. A team may have thousands of
-- copies and a builder shows this at every read, so no read walks them all:
--   the copies being built are found by their ids, which only grow: each
--   read looks at the ids made since the last one (at most LOOK_IDS) and
--   keeps the ones that are building or stalled until they are not;
--   the bill is worked out again once a second, not at every read;
--   once the request ends, what it showed last is kept (request.last) and
--   shown as it was, without looking at the project again.
-- What a read looks at is charged to the builder's team (D44).

local const = require("scripts.const")
local budget = require("scripts.core.budget")
local instances = require("scripts.core.instances")
local loop = require("scripts.core.loop")
local frontier = require("scripts.core.frontier")
local growth = require("scripts.core.growth")
local library = require("scripts.core.library")
local answer = require("scripts.circuit.answer")

local grow_report = {}

local virtual = answer.virtual
-- Instance ids one read looks at, at most.
local LOOK_IDS = 256
-- Ticks between two workings out of the next copy's bill.
local BILL_TICKS = 60
-- Estimated microseconds per record looked at (a copy's, a design's, an
-- item's): 20,000 copies took 2.7 ms to walk on a busy machine, 0.13 each,
-- and an id that is not the project's 0.04; doubled, for what else the
-- machine may be doing.
local LOOK_COST = 0.25

local function being_built(id)
  local instance = storage.instances[id]
  return instance ~= nil and instances.is_building(instance)
end

-- The set of copies being built, made from all the project has: none for a
-- project that has just started, every copy for a request that began before
-- the set was kept. Returns the records looked at.
local function gather(project, request)
  request.open, request.next_id = {}, storage.next_instance_id
  local looked = 0
  for id in pairs(project.instance_ids) do
    if being_built(id) then request.open[id] = true end
    looked = looked + 1
  end
  return looked
end

-- The copies made since the last read join the set. Returns the records looked at.
local function sight(project, request)
  local from = request.next_id
  local to = math.min(storage.next_instance_id - 1, from + LOOK_IDS - 1)
  for id = from, to do
    if project.instance_ids[id] and being_built(id) then request.open[id] = true end
  end
  request.next_id = math.max(from, to + 1)
  return math.max(0, to - from + 1)
end

-- The ghosts the set's copies have left; one that is not being built any
-- more leaves the set. Returns them and the records looked at.
local function ghosts_in(request)
  local ghosts, looked = 0, 0
  for id in pairs(request.open) do
    looked = looked + 1
    if being_built(id) then ghosts = ghosts + (storage.instances[id].ghosts_left or 0) else request.open[id] = nil end
  end
  return ghosts, looked
end

-- Open sockets, blocked sockets and copies built: fields of the project.
local function counts(project)
  local blocked = 0
  for reason, count in pairs(project.closed) do
    if loop.MARKED[reason] then blocked = blocked + count end
  end
  return #project.frontier + #project.parked, blocked, project.count - project.building
end

-- The design of the next copy and how many the socket offered: the first
-- the socket tried next would stamp (it may name another design or a pool),
-- else the project's own.
local function next_design(project)
  local i = frontier.next_index(project)
  local socket = i and project.frontier[i]
  local candidates = socket and growth.candidates(project, socket) or {}
  return candidates[1] or library.get(project.force_index, project.design_id), #candidates
end

-- The next copy's bill of materials as output keys, kept for BILL_TICKS.
-- Returns it and the records looked at.
local function bill(project, request)
  local kept = request.bill
  if kept and game.tick - kept.tick < BILL_TICKS then return kept.items, 0 end
  local design, offered = next_design(project)
  local items, cost = {}, design and design.prepared and design.prepared.ok and design.prepared.cost or {}
  for _, item in ipairs(cost) do
    local key = "item/" .. item.name
    items[key] = (items[key] or 0) + item.count
  end
  request.bill = { tick = game.tick, items = items }
  return items, offered + #cost
end

-- The status now, as output keys, and the records looked at.
local function look(project, request)
  local looked = request.open and sight(project, request) or gather(project, request)
  local ghosts, in_set = ghosts_in(request)
  local open, blocked, built = counts(project)
  local values = {
    [virtual("seb-ghosts-left")] = ghosts, [virtual("seb-open-sockets")] = open,
    [virtual("seb-blocked-sockets")] = blocked, [virtual("seb-built")] = built,
  }
  looked = looked + in_set
  if project.state == const.PROJECT_STATE.growing then
    local items, worked = bill(project, request)
    for key, count in pairs(items) do values[key] = count end
    looked = looked + worked
  end
  return values, looked
end

-- Adds the Grow's status to `values`, the output being written.
function grow_report.show(b, request, values)
  local shown = request.last
  if not shown then
    local project = storage.projects[request.project_id or 0]
    if project then
      local looked
      shown, looked = look(project, request)
      budget.charge(b.force_index, looked * LOOK_COST)
    end
    if request.finished then request.last, request.open, request.bill = shown or {}, nil, nil end
  end
  for key, count in pairs(shown or {}) do values[key] = count end
end

return grow_report
