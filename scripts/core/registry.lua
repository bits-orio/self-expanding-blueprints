-- The storage schema and its roots. The registry is the single source of
-- truth: the overlap index, the overlay and the GUIs are derived from it.

local scheduler = require("scripts.core.scheduler")
local footprints = require("scripts.core.footprints")

local const = require("scripts.const")

local registry = {}

local SCHEMA_VERSION = 1
local NONE = {}

-- Each force's projects by id (storage.force_projects[force_index] =
-- {[id] = true}), so what is counted for one force never walks every
-- force's projects. A save from before it existed builds it on first use.
local function project_index()
  local index = storage.force_projects
  if index then return index end
  index = {}
  for id, project in pairs(storage.projects) do
    local own = index[project.force_index] or {}
    index[project.force_index] = own
    own[id] = true
  end
  storage.force_projects = index
  return index
end

function registry.init_storage()
  storage.meta = storage.meta or { version = SCHEMA_VERSION }
  storage.libraries = storage.libraries or {}
  storage.instances = storage.instances or {}
  storage.projects = storage.projects or {}
  project_index()
  storage.ghost_regs = storage.ghost_regs or {}
  storage.entity_regs = storage.entity_regs or {}
  storage.players = storage.players or {}
  storage.renders = storage.renders or { instances = {}, projects = {} }
  storage.renders.next = storage.renders.next or {}   -- where building copies grow next (overlay.lua)
  storage.chunk_waits = storage.chunk_waits or {}   -- surface index -> {project id = true}
  storage.gallery = storage.gallery or { next_x = 0, cells = {} }   -- design pictures (gallery.lua)
  storage.builders = storage.builders or {}           -- unit number -> builder (circuit/builder.lua)
  storage.builder_regs = storage.builder_regs or {}   -- registration number -> builder unit number
  storage.next_instance_id = storage.next_instance_id or 1
  storage.next_project_id = storage.next_project_id or 1
  storage.next_design_id = storage.next_design_id or 1
  storage.budgets = storage.budgets or {}                   -- force index -> work account (budget.lua)
  storage.limit_overrides = storage.limit_overrides or {}   -- force index -> {limit = value} (limits.lua)
  scheduler.init_storage()
  footprints.init_storage()
end

function registry.new_instance_id()
  local id = storage.next_instance_id
  storage.next_instance_id = id + 1
  return id
end

function registry.new_project_id()
  local id = storage.next_project_id
  storage.next_project_id = id + 1
  return id
end

-- Design ids are unique across forces, so an id held by a player, a GUI tag
-- or the grow tool can never name another force's design.
function registry.new_design_id()
  local id = storage.next_design_id
  storage.next_design_id = id + 1
  return id
end

function registry.project(id)
  return id and storage.projects[id]
end

-- The ids of a force's projects, as a set to read (never to change).
function registry.project_ids(force_index)
  return project_index()[force_index] or NONE
end

function registry.add_project(project)
  storage.projects[project.id] = project
  local index = project_index()
  local own = index[project.force_index] or {}
  index[project.force_index] = own
  own[project.id] = true
end

-- The record goes for good: the project is forgotten.
function registry.remove_project(project)
  storage.projects[project.id] = nil
  local index = project_index()
  local own = index[project.force_index]
  if not own then return end
  own[project.id] = nil
  if next(own) == nil then index[project.force_index] = nil end
end

-- Per-player GUI and tool state, created on first use.
function registry.player(player_index)
  local state = storage.players[player_index]
  if not state then
    state = {}
    storage.players[player_index] = state
  end
  return state
end

-- The player's grow options, with their defaults: grow east and south, the
-- materials gate on, no count limit.
-- How many copies a grow from the window stops after: the player's count,
-- const.GROW_COPIES until they set one, none (nil) once they cleared it
-- (stored as false). A fill (`fill`) stops at its rectangle unless the
-- player set a count. A plan stops after its own count, const.PLAN_COPIES
-- until set.
function registry.grow_count(options, fill)
  if options.dry_run then return options.plan_count or const.PLAN_COPIES end
  if options.max_instances == nil then return not fill and const.GROW_COPIES or nil end
  return options.max_instances or nil
end

function registry.grow_options(player_index)
  local state = registry.player(player_index)
  state.grow = state.grow or {
    directions = { [defines.direction.east] = true, [defines.direction.south] = true },
    materials = true, retire_depleted = false,
  }
  return state.grow
end

function registry.drop_player(player_index)
  storage.players[player_index] = nil
end

return registry
