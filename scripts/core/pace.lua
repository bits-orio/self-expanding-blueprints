-- What a step of the growth loop costs, counted two ways.
--   The project's own pace: each run of its advance has WORK_BUDGET units.
--   A copy placed costs four socket checks' worth, more for a big design
--   (a unit per 32 parts: spike S5 measured about 10 microseconds per
--   entity), for a real stamp and a plan's step alike. Another step goes
--   ahead only while the work left covers the last one's cost, so a design
--   of some hundreds of parts places at most one copy per run.
--   The force's share of server time (budget.lua, D44): every step charges
--   the work it did, in estimated microseconds (work.lua: the spots and
--   chunks looked at, probes, parts checked, copies and parts built).
--   While the share is used up the force's projects wait in a line
--   (storage.turns[force_index]), served from the front when the share is
--   there again, so they take turns instead of the first in the queue
--   taking it all.

local const = require("scripts.const")
local budget = require("scripts.core.budget")
local scheduler = require("scripts.core.scheduler")
local work = require("scripts.core.work")

local pace = {}

-- advance(project): the growth loop's advance, set by loop.lua, which
-- serves the line.
pace.hooks = {}

local PARTS_PER_UNIT = 32

pace.STAMP_COST = 4
pace.WORK_BUDGET = const.ADVANCE_BUDGET * pace.STAMP_COST

-- One cost for a step that checked or built `parts` parts, real or planned.
function pace.units(parts)
  return math.max(pace.STAMP_COST, math.ceil(parts / PARTS_PER_UNIT))
end

-- A step's result (growth.try) charged to the project's force: what its
-- last design tried did (growth.try paid for any before it).
function pace.charge(project, result)
  work.charge(project.force_index, result.work)
end

-- Ghosts built outside a stamp (a plan's look-only ghosts), charged like one;
-- `poles` of them electric poles.
function pace.charge_ghosts(project, count, poles)
  work.charge(project.force_index, work.new { ghosts = count, poles = poles })
end

-- A force's line, if it ever had one: {ids = {project id, ...} front
-- first, waiting = {[id] = true}, due = the tick it is served at, serving =
-- the id of the project having its turn}.
local function line_if_any(force_index)
  return storage.turns and storage.turns[force_index]
end

local function line_of(force_index)
  storage.turns = storage.turns or {}
  local line = storage.turns[force_index]
  if not line then
    line = { ids = {}, waiting = {} }
    storage.turns[force_index] = line
  end
  return line
end

function pace.in_line(project)
  local line = line_if_any(project.force_index)
  return line ~= nil and line.waiting[project.id] == true
end

-- Whether the project may take a step now: its force has its share, and
-- no project of the force waits in line before it.
function pace.ready(project)
  local line = line_if_any(project.force_index)
  if line and #line.ids > 0 and line.serving ~= project.id then return false end
  return budget.ready(project.force_index)
end

local function arm(force_index, line)
  local due = game.tick + budget.wait(force_index)
  if line.due and line.due <= due then return end
  line.due = due
  scheduler.at(due, { kind = "turn", id = force_index })
end

-- The project waits at the back of its force's line, once.
function pace.join(project)
  local line = line_of(project.force_index)
  if line.waiting[project.id] then return end
  line.waiting[project.id] = true
  line.ids[#line.ids + 1] = project.id
  arm(project.force_index, line)
end

-- Project `id`, out of the line, for one run of its advance (none for one
-- forgotten since it joined).
local function serve(line, id)
  line.waiting[id] = nil
  local project = storage.projects[id]
  if not project then return end
  line.serving = id
  pace.hooks.advance(project)
  line.serving = nil
end

-- The share is there again: the projects in line now go, front first, each
-- for one run of its advance, for as long as the share lasts. One that
-- joins the back meanwhile (its run used the share up, or a pool's step
-- stopped early with the share left) waits for the next turn, so none runs
-- twice in one.
scheduler.register("turn", function(item)
  local line = line_if_any(item.id)
  if not line then return end
  line.due = nil
  for _ = 1, #line.ids do
    if not budget.ready(item.id) then break end
    serve(line, table.remove(line.ids, 1))
  end
  if #line.ids > 0 then arm(item.id, line) end
end)

-- The rate of a team's share of server time changed (a map setting, or
-- set_limits; no force: every team's): its line, if projects wait in it,
-- is served as soon as the new rate allows.
function pace.rate_changed(force_index)
  for index, line in pairs(storage.turns or {}) do
    if (not force_index or index == force_index) and #line.ids > 0 then
      line.due = nil
      arm(index, line)
    end
  end
end

-- A force merged or released: its line goes with its projects, as a new
-- force may get its index.
function pace.drop_force(force_index)
  if storage.turns then storage.turns[force_index] = nil end
end

return pace
