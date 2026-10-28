-- Brings records from an older save up to date, on configuration change.
-- 0.1.0 projects lack the fields 0.2 added; their stalled copies were never
-- put in a stalled set (it fills only as states change); and 0.1.0 left the
-- outlines of a stopped project's copies on the map. Saves from before D45
-- kept every project that ever ended (the per-force index of projects is
-- built by registry.init_storage, which runs first). They also kept every
-- retired copy (forgetting.sweep).

local const = require("scripts.const")
local overlay = require("scripts.render.overlay")
local retention = require("scripts.core.retention")
local forgetting = require("scripts.core.forgetting")
local instances = require("scripts.core.instances")
local tracking = require("scripts.core.tracking")

local migrations = {}

local NEW_PROJECT_FIELDS = { "history", "stalled", "waiting_ore", "planned", "plan_chunks" }

local function fill_projects()
  for _, project in pairs(storage.projects) do
    for _, field in ipairs(NEW_PROJECT_FIELDS) do project[field] = project[field] or {} end
  end
end

local function settle_instances()
  for id, instance in pairs(storage.instances) do
    local project = instance.project_id and storage.projects[instance.project_id]
    if instance.project_id and (not project or project.state == const.PROJECT_STATE.stopped) then
      overlay.drop_instance(id)
    elseif project and instance.state == const.STATE.stalled then
      project.stalled[id] = instance.reason or const.REASON.no_progress
    end
  end
end

-- The oldest version among each project's copies (0.1.0 never kept it).
local function oldest_versions()
  for _, project in pairs(storage.projects) do
    if not project.oldest_version then
      for id in pairs(project.instance_ids or {}) do
        local instance = storage.instances[id]
        if instance and instance.state ~= const.STATE.retired then
          project.oldest_version = math.min(project.oldest_version or instance.version, instance.version)
        end
      end
    end
  end
end

-- 0.2: "How growing works" left the main window for its own; the old
-- per-player toggle for the inline panel means nothing now.
local function drop_help_toggle()
  for _, state in pairs(storage.players or {}) do state.help_open = nil end
end

-- Each force keeps only its newest ended projects (retention.lua).
local function forget_old_projects()
  local forces = {}
  for force_index in pairs(storage.force_projects) do forces[#forces + 1] = force_index end
  for _, force_index in ipairs(forces) do retention.prune(force_index) end
end

-- Copies stamped before they kept their version's prepared data look under
-- their whole footprint (under.lua); one still of its design's current
-- version gets that version's, so its recounts look under its parts.
local function attach_prepared()
  for _, instance in pairs(storage.instances) do
    local lib = not instance.prepared and storage.libraries[instance.force_index]
    local design = lib and lib.designs[instance.design_id]
    local prepared = design and design.prepared
    if prepared and prepared.ok and prepared.version == instance.version then instance.prepared = prepared end
  end
end

-- A copy whose drills are watched goes when they run dry, even once its
-- finished project is forgotten; older saves watched them unmarked
-- (depletion.watch_drills marks them now).
local function mark_watched_drills()
  for _, instance in pairs(storage.instances) do
    if instance.drill_areas then instance.retire_depleted = true end
  end
end

-- A copy whose parts were all removed is released by its recount (D55).
-- One emptied before 0.2.4 is recounted once.
local function recount_emptied()
  local STATE = const.STATE
  for _, instance in pairs(storage.instances) do
    local state = instance.state
    if state ~= STATE.retiring and state ~= STATE.retired and (instance.expected or 0) > 0
      and instances.built_entities(instance) == 0 then
      tracking.mark_dirty(instance)
    end
  end
end

-- Projects and designs per team are unlimited by default since 0.2.5; a
-- save still on the old defaults (20 projects, 100 designs) moves with
-- them, once, so a limit an admin sets later stays.
local OLD_DEFAULTS = { ["seb-max-projects-per-force"] = 20, ["seb-max-designs-per-force"] = 100 }

local function unlimited_defaults()
  if storage.unlimited_defaults then return end
  storage.unlimited_defaults = true
  for name, old in pairs(OLD_DEFAULTS) do
    local setting = settings.global[name]
    if setting and setting.value == old then settings.global[name] = { value = 0 } end
  end
end

function migrations.run()
  forgetting.sweep()
  fill_projects()
  settle_instances()
  oldest_versions()
  drop_help_toggle()
  mark_watched_drills()
  forget_old_projects()
  attach_prepared()
  recount_emptied()
  unlimited_defaults()
end

return migrations
