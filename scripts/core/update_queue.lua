-- Updates in place of many copies at once (a project's update button, a
-- research that upgrades a design, the remote interface's update_project)
-- wait in a line per force and are made over several runs of the due-tick
-- queue: a few copies per run, and only while the team's share of server
-- time lasts (budget.lua, D44). One click on a project of a thousand copies
-- does not update them all in one tick; each update is one piece of work,
-- charged as it is made (update.cost).
--   A copy waits in the line once. One that has been updated meanwhile, or
--   retires, or whose record is gone, is passed over at its turn.
--   Each request is a batch. Once its last copy has had its turn, the
--   versions of the projects it updated are counted again, once each, and
--   it reports through the hook of its kind (projects.lua, research.lua).
-- storage.update_lines[force_index] = {ids = {[n] = instance id}, first,
-- last, batch_of = {[instance id] = batch id}, batches = {[id] = batch},
-- next_batch, due}; a batch is {id, kind, force_index, left, done, refused,
-- by_design = {[design id] = {done, refused}}, projects = {[id] = true}}
-- plus its kind's own fields.

local scheduler = require("scripts.core.scheduler")
local budget = require("scripts.core.budget")
local library = require("scripts.core.library")
local update = require("scripts.core.update")

local update_queue = {}

-- done[kind](batch): set by the module that queues batches of that kind.
update_queue.done = {}

local KIND = "update-copies"
local PER_RUN = 4      -- copies updated per run at most (and library.RUN_PARTS parts)
local MAX_TURNS = 64   -- turns per run at most, copies passed over included

local function lines()
  storage.update_lines = storage.update_lines or {}
  return storage.update_lines
end

local function line_of(force_index)
  local line = lines()[force_index]
  if not line then
    line = { ids = {}, first = 1, last = 0, batch_of = {}, batches = {}, next_batch = 1 }
    lines()[force_index] = line
  end
  return line
end

local function arm(force_index, line, tick)
  if line.due and line.due <= tick then return end
  line.due = tick
  scheduler.at(tick, { kind = KIND, id = force_index })
end

-- Queues the copies (ids, in the order they go) as one batch, a table of
-- the kind's own fields with its `kind`. Returns how many joined the line:
-- a copy already in it keeps its place in its own batch.
function update_queue.add(force_index, ids, batch)
  local line = line_of(force_index)
  batch.id, batch.force_index = line.next_batch, force_index
  batch.left, batch.done, batch.refused, batch.by_design, batch.projects = 0, 0, 0, {}, {}
  for _, id in ipairs(ids) do
    if not line.batch_of[id] then
      line.last = line.last + 1
      line.ids[line.last], line.batch_of[id] = id, batch.id
      batch.left = batch.left + 1
    end
  end
  if batch.left == 0 then
    if line.first > line.last then lines()[force_index] = nil end
    return 0
  end
  line.next_batch = line.next_batch + 1
  line.batches[batch.id] = batch
  arm(force_index, line, game.tick + budget.wait(force_index))
  return batch.left
end

local function count(batch, instance, ok)
  local tally = batch.by_design[instance.design_id] or { done = 0, refused = 0 }
  batch.by_design[instance.design_id] = tally
  local field = ok and "done" or "refused"
  batch[field], tally[field] = batch[field] + 1, tally[field] + 1
  if instance.project_id then batch.projects[instance.project_id] = true end
end

local function finish(line, batch)
  line.batches[batch.id] = nil
  for id in pairs(batch.projects) do
    local project = storage.projects[id]
    if project then update.recount_project(project) end
  end
  local done = update_queue.done[batch.kind]
  if done then done(batch) end
end

-- The front copy has its turn: updated if it still needs to be. Returns the
-- parts that took, or nil when it was passed over.
local function serve(line)
  local id = line.ids[line.first]
  line.ids[line.first], line.first = nil, line.first + 1
  local batch = line.batches[line.batch_of[id]]
  line.batch_of[id] = nil
  local instance = storage.instances[id]
  local parts
  if instance and update.outdated(instance) then
    parts = library.parts_of(library.get(instance.force_index, instance.design_id))
    count(batch, instance, update.run(instance, true))
  end
  batch.left = batch.left - 1
  if batch.left == 0 then finish(line, batch) end
  return parts
end

local function run(item, now)
  local force_index = item.id
  local line = lines()[force_index]
  if not line or (line.due and line.due > now) then return end
  line.due = nil
  local updated, parts, turns = 0, 0, 0
  while line.first <= line.last and updated < PER_RUN and parts < library.RUN_PARTS and turns < MAX_TURNS
    and budget.ready(force_index) do
    local took = serve(line)
    if took then updated, parts = updated + 1, parts + took end
    turns = turns + 1
  end
  if line.first > line.last then
    lines()[force_index] = nil
    return
  end
  arm(force_index, line, now + budget.wait(force_index))
end
scheduler.register(KIND, run)

-- Whether the copy waits in its force's line.
function update_queue.queued(instance)
  local line = storage.update_lines and storage.update_lines[instance.force_index]
  return line ~= nil and line.batch_of[instance.id] ~= nil
end

-- How many copies a project's own requests still have waiting.
function update_queue.waiting(project)
  local line = storage.update_lines and storage.update_lines[project.force_index]
  local n = 0
  for _, batch in pairs(line and line.batches or {}) do
    if batch.project_id == project.id then n = n + batch.left end
  end
  return n
end

return update_queue
