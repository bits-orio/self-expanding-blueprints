-- Stopping a project and taking copies of it off the map with it: the ones
-- robots have not finished (a Shift + click on Stop), or every one (an
-- undone click, undo.lua). Each copy is retired, so exactly what it built
-- goes (instances.retire).

local const = require("scripts.const")
local instances = require("scripts.core.instances")
local projects = require("scripts.core.projects")

local removal = {}

local STATE = const.STATE

removal.UNBUILT, removal.ALL = "unbuilt", "all"

-- The project's copies in the order they were placed: its ids are taken
-- first, as a stopped project may be forgotten at once (retention.lua).
local function copies_of(project)
  local ids = {}
  for id in pairs(project.instance_ids) do ids[#ids + 1] = id end
  table.sort(ids)
  return ids
end

-- Stops the project and retires its copies: `which` is removal.UNBUILT
-- (those not complete) or removal.ALL. Returns how many are being removed.
function removal.stop(project, which)
  local ids, n = copies_of(project), 0
  projects.stop(project)
  for _, id in ipairs(ids) do
    local instance = storage.instances[id]
    local wanted = instance and (which == removal.ALL or instance.state ~= STATE.complete)
    if wanted and instances.retire(instance) then n = n + 1 end
  end
  return n
end

return removal
