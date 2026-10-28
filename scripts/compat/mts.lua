-- Multi-Team Support recycles team forces: a released team's force is reset
-- and handed to the next team with the same index. Its designs, projects and
-- instance records must not carry over, so they are dropped on mts-v1's
-- on_team_released (payload: force_name). Not on_force_reset: that also fires
-- when an admin only resets research.

local lifecycle = require("scripts.lifecycle")

local mts = {}

local function on_team_released(event)
  local force = game.forces[event.force_name]
  if force then lifecycle.drop_force(force.index) end
end

-- From on_init and on_load: event ids are generated afresh every session.
-- get_event_id only reads a table, so it is safe while loading.
function mts.subscribe()
  if not remote.interfaces["mts-v1"] then return end
  local id = remote.call("mts-v1", "get_event_id", "on_team_released")
  if id then script.on_event(id, on_team_released) end
end

return mts
