-- The bar over a projects list that acts on every project in it at once:
-- pause, resume, retry their blocked spots, clear the finished ones off the
-- list, stop them all. A list of many projects (a click starts each) needs
-- no row-by-row clicking.

local projects = require("scripts.core.projects")
local cursor = require("scripts.cursor")

local project_bulk = {}

local OPS = { "pause", "resume", "retry", "clear", "stop" }

local ACTS = {
  pause = function(project, player) return projects.pause(project, player) end,
  resume = function(project, player) return projects.resume(project, player) end,
  retry = function(project, player) return projects.retry(project, player) > 0 end,
  -- A cleared project is forgotten as an ended one is: its copies stay,
  -- and those that retire when their ore runs out still do.
  clear = function(project)
    if not projects.is_done(project) then return false end
    projects.discard(project)
    return true
  end,
  stop = function(project)
    projects.stop(project)
    return true
  end,
}

function project_bulk.build(holder)
  local bar = holder.add { type = "flow", name = "proj_bulk", direction = "horizontal" }
  for _, op in ipairs(OPS) do
    bar.add {
      type = "button", style = op == "stop" and "red_button" or "button", caption = { "seb-gui.bulk-" .. op },
      tooltip = { "seb-gui.bulk-" .. op .. "-tooltip" }, tags = { seb = "bulk-projects", op = op },
    }
  end
end

-- `list`: the projects the player's window lists.
function project_bulk.run(player, op, list)
  local act = ACTS[op]
  if not act then return end
  local n = 0
  for _, project in ipairs(list) do
    if storage.projects[project.id] and act(project, player) then n = n + 1 end
  end
  cursor.say(player, { "seb-message.bulk-" .. op, n })
end

return project_bulk
