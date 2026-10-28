-- What a project hears from its copies: one finished (open its sockets, or
-- wait for its ore), came out incomplete, stalled, was updated in place,
-- ran out of ore. Each event is an instances.lua or depletion.lua hook.

local const = require("scripts.const")
local registry = require("scripts.core.registry")
local instances = require("scripts.core.instances")
local frontier = require("scripts.core.frontier")
local history = require("scripts.core.history")
local loop = require("scripts.core.loop")
local depletion = require("scripts.core.depletion")
local overlay = require("scripts.render.overlay")

local copy_events = {}

local STATE = const.PROJECT_STATE
local INSTANCE = const.STATE

-- The window learns through the same hook the growth loop uses.
local function changed(project)
  if loop.hooks.changed then loop.hooks.changed(project) end
end

local function project_of(instance)
  local project = registry.project(instance.project_id)
  if project and project.state ~= STATE.stopped then return project end
end

-- Whether the copy goes once its drills have nothing left to mine: its
-- project says so, unless it stopped; with its finished project forgotten
-- since, the copy's own mark says so (depletion.watch_drills).
local function retires_dry(instance)
  local project = registry.project(instance.project_id)
  if project then return project.state ~= STATE.stopped and project.rules.retire_depleted end
  return instance.retire_depleted == true
end

-- A finished copy opens its sockets now, or, when its ore sensors still see
-- ore, once that ore is gone (depletion.lua).
local function finished(project, instance)
  if project.rules.retire_depleted then depletion.watch_drills(instance) end
  if instance.opened_early then return end
  -- Past the count its sockets can only close, so waiting for ore is moot.
  local counted_out = project.rules.max_instances and project.count >= project.rules.max_instances
  if counted_out or depletion.ready(instance) then return frontier.open(project, instance) end
  project.waiting_ore = project.waiting_ore or {}
  project.waiting_ore[instance.id] = true
  history.add(project, { kind = "waiting-ore", instance_id = instance.id })
  overlay.refresh_instance(instance)
end

local function settle(instance, opened)
  local project = project_of(instance)
  if not project then return end
  project.building = math.max(0, project.building - 1)
  loop.wake_force(project.force_index)
  if opened then
    finished(project, instance)
  elseif instance.state == INSTANCE.incomplete then
    history.add(project, { kind = "incomplete", instance_id = instance.id })
  end
  loop.queue_advance(project, 1)
  changed(project)
end

-- An update in place finished: a copy that never opened its sockets opens
-- them now; one that had keeps going (its drills watched again).
instances.hooks.reopened = function(instance)
  local project = project_of(instance)
  if not project then return end
  finished(project, instance)
  loop.queue_advance(project, 1)
  changed(project)
end

instances.hooks.updated = function(instance)
  if retires_dry(instance) then depletion.watch_drills(instance) end
end

depletion.hooks.ore_gone = function(instance)
  local project = project_of(instance)
  if not project then return end
  if project.waiting_ore then project.waiting_ore[instance.id] = nil end
  history.add(project, { kind = "ore-gone", instance_id = instance.id })
  frontier.open(project, instance)
  overlay.refresh_instance(instance)
  loop.queue_advance(project, 1)
  changed(project)
end

-- Its drills have nothing left to mine: it goes, as a right-drag would take
-- it. Its own sockets still open: growth.lua lets a copy retired for
-- depletion parent the copies after it. A copy whose project is forgotten
-- goes too, and its record with it (forgetting.lua).
depletion.hooks.dry = function(instance)
  if not retires_dry(instance) then return end
  local project = project_of(instance)
  if project then history.add(project, { kind = "depleted", instance_id = instance.id }) end
  instance.retired_for = "depleted"
  instances.retire(instance)
  if project then changed(project) end
end

instances.hooks.completed = function(instance) settle(instance, true) end
instances.hooks.incomplete = function(instance) settle(instance, false) end

-- The project's set of stalled copies follows every instance state change;
-- a copy that stalls, or stalls for a new reason, goes into the history.
-- A copy waiting for its ore that leaves (retired) no longer holds the
-- project open.
local function leave_ore_wait(project, instance)
  if not (project.waiting_ore and project.waiting_ore[instance.id]) then return false end
  if instance.state ~= INSTANCE.retiring and instance.state ~= INSTANCE.retired then return false end
  project.waiting_ore[instance.id] = nil
  loop.queue_advance(project, 1)
  return true
end

instances.hooks.state = function(instance, old_state)
  local project = project_of(instance)
  if not project then return end
  if leave_ore_wait(project, instance) then changed(project) end
  local stalled = project.stalled or {}
  project.stalled = stalled
  if instance.state == INSTANCE.stalled then
    if stalled[instance.id] ~= instance.reason then
      stalled[instance.id] = instance.reason
      history.add(project, { kind = "stalled", instance_id = instance.id, reason = instance.reason })
    end
  elseif old_state == INSTANCE.stalled then
    stalled[instance.id] = nil
  else
    return
  end
  changed(project)
end

return copy_events
