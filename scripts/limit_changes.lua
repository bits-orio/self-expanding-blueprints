-- A limit changed, and what waited on the old one looks again at once: the
-- remote interface's set_limits and clear_limits tell it for one team, the
-- map settings for every team (on_runtime_mod_setting_changed, which the
-- engine raises for a player's change only; the builders timer, builder.lua,
-- notices a builder limit that a script changed).
--   building  projects held at the capacity gate try again (loop.lua)
--   builders  builders over the limit take the places that are free (roster.lua)
--   work      what waits for a share of server time at the old rate: the
--             team's line of projects (pace.lua) and its builders (builder.lua)
-- Each takes a force index, or nil for every force.

local loop = require("scripts.core.loop")
local pace = require("scripts.core.pace")
local builder = require("scripts.circuit.builder")

local limit_changes = {}

local function wake_projects(force_index)
  if force_index then return loop.wake_force(force_index) end
  for _, force in pairs(game.forces) do loop.wake_force(force.index) end
end

local function rebalance_builders(force_index)
  builder.rebalance(force_index)
end

local function rearm_waits(force_index)
  pace.rate_changed(force_index)
  builder.rate_changed(force_index)
end

-- By the limit's name in limits.lua, and the order they run in.
local ACTION = { building = wake_projects, builders = rebalance_builders, work = rearm_waits }
local ORDER = { "building", "builders", "work" }

-- The map settings that set those limits (limits.lua). The server-wide
-- share of server time rearms what waits for a team's share as well.
local LIMIT_OF_SETTING = {
  ["seb-max-building-per-force"] = "building", ["seb-max-builders-per-force"] = "builders",
  ["seb-work-per-force"] = "work", ["seb-work-per-tick"] = "work",
}

-- One force's limits changed: `keys` holds the limits that were set
-- (set_limits), or is nil when any may have changed (clear_limits). Another
-- mod may set limits before this one's on_init: nothing waits yet.
function limit_changes.of_force(force_index, keys)
  if not storage.projects then return end
  for _, key in ipairs(ORDER) do
    if not keys or keys[key] ~= nil then ACTION[key](force_index) end
  end
end

function limit_changes.on_setting_changed(event)
  local key = LIMIT_OF_SETTING[event.setting]
  if key then ACTION[key](nil) end
end

return limit_changes
