-- How many projects a force keeps (DESIGN.md D45), so no team can grow the
-- save, or the work of counting its projects, without bound:
--   live plans   dry runs not stopped (planning, or planned and waiting to
--                be built), at most limits "plans": a new plan stops the
--                oldest ones (projects.lua)
--   ended        stopped projects, and finished real ones: the newest
--                limits "ended_projects" by id stay (const.ENDED_PROJECTS_KEPT
--                unless set_limits says otherwise; 0 keeps all), so a team
--                still sees how its recent growth ended; older ones are
--                forgotten
-- A forgotten project leaves nothing behind but its copies, which go on as
-- a stopped project's do: every reader of storage.projects takes a missing
-- id for a project that is gone. One thing stays: the copies of a finished
-- project that removes copies whose ore runs out still go when it does
-- (their drills stay watched, copy_events.lua).

local const = require("scripts.const")
local registry = require("scripts.core.registry")
local limits = require("scripts.core.limits")
local frontier = require("scripts.core.frontier")
local previews = require("scripts.core.previews")
local depletion = require("scripts.core.depletion")
local instances = require("scripts.core.instances")
local overlay = require("scripts.render.overlay")

local retention = {}

local STATE = const.PROJECT_STATE

local function by_id(a, b)
  return a.id < b.id
end

-- The force's projects that pass `keep`, oldest first.
local function projects_where(force_index, keep)
  local list = {}
  for id in pairs(registry.project_ids(force_index)) do
    local project = storage.projects[id]
    if project and keep(project) then list[#list + 1] = project end
  end
  table.sort(list, by_id)
  return list
end

local function live_plan(project)
  return project.dry_run and project.state ~= STATE.stopped
end

-- A finished plan still waits to be built, so only a real project ends by
-- finishing.
local function ended(project)
  return project.state == STATE.stopped or (project.state == STATE.finished and not project.dry_run)
end

-- The live plans to stop, oldest first, so one more fits under the force's
-- limit; none without one.
function retention.plans_to_drop(force_index)
  local cap = limits.of(force_index, "plans")
  if cap == 0 then return {} end
  local list = projects_where(force_index, live_plan)
  local over = {}
  for i = 1, #list - cap + 1 do over[i] = list[i] end
  return over
end

-- Takes everything a project drew or asked for off the map and out of the
-- queues: its marks, its copies' marks, its look-only ghosts, its open
-- sockets and what its copies wait for at the ore. Its copies stay. With
-- `keep_drills` (a finished project forgotten) its copies' drills stay
-- watched.
function retention.let_go(project, keep_drills)
  previews.clear(project)
  frontier.clear(project)
  overlay.drop_project(project.id)
  for id in pairs(project.instance_ids) do
    overlay.drop_instance(id)
    local instance = storage.instances[id]
    if instance and keep_drills then
      depletion.forget_ore(instance)
    elseif instance then
      depletion.let_go(instance)
    end
  end
end

function retention.forget(project)
  retention.let_go(project, project.state == STATE.finished)
  local waiting = storage.chunk_waits[project.surface_index]
  if waiting then waiting[project.id] = nil end
  instances.forget_retired_of(project.id)
  registry.remove_project(project)
end

-- A project of the force ended: the oldest ended ones past what a force
-- keeps are forgotten. Returns them, for the window to drop their rows.
function retention.prune(force_index)
  local keep = limits.of(force_index, "ended_projects")
  if keep == 0 then return {} end
  local list = projects_where(force_index, ended)
  local gone = {}
  for i = 1, #list - keep do
    retention.forget(list[i])
    gone[i] = list[i]
  end
  return gone
end

return retention
