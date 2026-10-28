-- The map's limits per team (settings.lua, DESIGN.md D43-D45), each read
-- through here so a server can give one force its own value: the remote
-- interface's set_limits stores per-force overrides (an MTS admin tool, and
-- how tests and tips give their force other limits without touching
-- everyone else's). A number of zero means no limit.

local const = require("scripts.const")

local limits = {}

local SETTING = {
  projects = "seb-max-projects-per-force",
  building = "seb-max-building-per-force",
  plans = "seb-max-plans-per-force",
  designs = "seb-max-designs-per-force",
  design_parts = "seb-max-design-parts",
  builders = "seb-max-builders-per-force",
  builders_charted_only = "seb-builders-charted-only",
  work = "seb-work-per-force",
}

-- Limits with no map setting: a fixed value set_limits can still override
-- for one force (the tests' shared force keeps every project it ended).
local FIXED = {
  ended_projects = const.ENDED_PROJECTS_KEPT,
}

-- Values for the whole server, a map setting each and never one force's:
-- the server's time per tick for every team together (server_budget.lua).
local SERVER = {
  work = "seb-work-per-tick",
}

local function default(key)
  if FIXED[key] ~= nil then return FIXED[key] end
  return settings.global[SETTING[key]].value
end

function limits.of(force_index, key)
  local overrides = storage.limit_overrides and storage.limit_overrides[force_index]
  local value = overrides and overrides[key]
  if value ~= nil then return value end
  return default(key)
end

function limits.server(key)
  return settings.global[SERVER[key]].value
end

-- Whether the force has used up its limit of `key`, with `used` taken.
function limits.reached(force_index, key, used)
  local cap = limits.of(force_index, key)
  return cap > 0 and used >= cap
end

-- A value of the setting's own type: a whole number from zero, or a boolean.
local function valid(key, value)
  if type(default(key)) == "boolean" then return type(value) == "boolean" end
  return type(value) == "number" and value >= 0 and value % 1 == 0
end

-- Overrides for one force, {key = value}, added to any it has (clear drops
-- them all). Returns true, or false and the first unknown key or bad value.
function limits.set(force_index, overrides)
  for key, value in pairs(overrides) do
    if not ((SETTING[key] or FIXED[key] ~= nil) and valid(key, value)) then return false, key end
  end
  storage.limit_overrides = storage.limit_overrides or {}
  local mine = storage.limit_overrides[force_index] or {}
  for key, value in pairs(overrides) do mine[key] = value end
  storage.limit_overrides[force_index] = mine
  return true
end

-- Every limit as it applies to the force now.
function limits.all(force_index)
  local out = {}
  for key in pairs(SETTING) do out[key] = limits.of(force_index, key) end
  for key in pairs(FIXED) do out[key] = limits.of(force_index, key) end
  return out
end

function limits.clear(force_index)
  if storage.limit_overrides then storage.limit_overrides[force_index] = nil end
end

-- How many designs the force may keep: the map's limit, never past
-- const.MAX_LIBRARY_DESIGNS (which is all that a limit of 0 leaves).
function limits.max_designs(force_index)
  local cap = limits.of(force_index, "designs")
  return (cap > 0 and cap < const.MAX_LIBRARY_DESIGNS) and cap or const.MAX_LIBRARY_DESIGNS
end

return limits
