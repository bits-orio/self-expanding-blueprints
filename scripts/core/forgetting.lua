-- Forgetting retired copies (DESIGN.md D45). A copy's record goes once it has
-- retired and raised on_instance_retired, so a team that stamps and removes
-- copies all day leaves nothing in the save. One kind stays while its project
-- grows: a copy retired for depletion still parents the sockets it opened
-- (growth.lua), so its record is kept until the project ends.

local const = require("scripts.const")
local footprints = require("scripts.core.footprints")
local depletion = require("scripts.core.depletion")
local overlay = require("scripts.render.overlay")

local forgetting = {}

local STATE = const.STATE
local PROJECT = const.PROJECT_STATE

-- Takes a copy out of what finds it: the overlap index, what it watches for
-- and what is drawn for it. A retiring copy leaves them before its event; a
-- copy dropped with its surface or force leaves them as it goes.
function forgetting.unindex(instance)
  footprints.remove(instance)
  depletion.forget(instance)
  overlay.drop_instance(instance.id)
end

-- Drops the record of a copy that has left the indexes, and its project's
-- note of it.
function forgetting.forget(instance)
  storage.instances[instance.id] = nil
  local project = instance.project_id and storage.projects[instance.project_id]
  if project then project.instance_ids[instance.id] = nil end
end

-- Whether the copy's project still grows from it.
local function parents_growth(instance)
  if instance.retired_for ~= "depleted" then return false end
  local project = instance.project_id and storage.projects[instance.project_id]
  return project ~= nil and (project.state == PROJECT.growing or project.state == PROJECT.paused)
end

-- A copy has finished retiring and its event is out.
function forgetting.after_retire(instance)
  if not parents_growth(instance) then forgetting.forget(instance) end
end

-- The ids of a project's copies. Once the project is dropped they can only
-- be found by asking every copy, so forget before dropping it.
local function ids_of(project_id)
  local project = storage.projects[project_id]
  if project then return project.instance_ids end
  local ids = {}
  for id, instance in pairs(storage.instances) do
    if instance.project_id == project_id then ids[id] = true end
  end
  return ids
end

-- A project ended (stopped, finished, or forgotten): nothing grows from its
-- retired copies any more.
function forgetting.retired_of(project_id)
  for id in pairs(ids_of(project_id)) do
    local instance = storage.instances[id]
    if instance and instance.state == STATE.retired then forgetting.forget(instance) end
  end
end

-- Saves from before D45 hold every copy ever retired.
function forgetting.sweep()
  for _, instance in pairs(storage.instances) do
    if instance.state == STATE.retired and not parents_growth(instance) then forgetting.forget(instance) end
  end
end

return forgetting
