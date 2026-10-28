-- Write tools for AI Agent Bridge (DESIGN.md section 6), offered only while
-- a server admin has the map setting "seb-agent-write-tools" on: an agent
-- may then pause, resume or stop the asking team's growth projects and
-- start growth from a map position. Each tool acts only on the force the
-- bridge injects, and refuses (an error the agent reads) while the setting
-- is off.

local const = require("scripts.const")
local geometry = require("scripts.core.geometry")
local projects = require("scripts.core.projects")

local agent_write = {}

local SETTING = "seb-agent-write-tools"
local PROJECT = { id = "integer! the project number from seb_projects" }

agent_write.MANIFEST = {
  seb_pause_project = {
    desc = "Self-Expanding Blueprints: pause one of the team's growth projects. It keeps its copies and can be resumed.",
    params = PROJECT,
  },
  seb_resume_project = {
    desc = "Self-Expanding Blueprints: resume a paused growth project of the team.",
    params = PROJECT,
  },
  seb_stop_project = {
    desc = "Self-Expanding Blueprints: stop a growth project for good. It grows no more and its marks leave the map; "
      .. "copies already placed stay, and robots finish the ones under construction.",
    params = PROJECT,
  },
  seb_grow = {
    desc = "Self-Expanding Blueprints: grow one of the team's designs from a map position, as the window's Grow does: copies "
      .. "repeat east and south (or the given sides) over charted land, as materials allow, until water, cliffs, "
      .. "buildings or the count stop them. Returns the new project's number.",
    params = {
      design = "integer! the design number from seb_designs",
      x = "number! map x of the first copy",
      y = "number! map y of the first copy",
      count = "integer how many copies at most (default: no limit)",
      sides = "string the sides a plain design grows toward, comma-separated (default 'east,south')",
      surface = "string the surface name (default 'nauvis')",
    },
  },
}

function agent_write.enabled()
  return settings.global[SETTING].value == true
end

local SIDES = { north = geometry.NORTH, east = geometry.EAST, south = geometry.SOUTH, west = geometry.WEST }

local function sides(text)
  if text == nil then return nil end
  if type(text) ~= "string" then error("sides: a text like 'east,south'", 0) end
  local list = {}
  for word in text:gmatch("[^,%s]+") do
    list[#list + 1] = SIDES[word:lower()] or error("sides: no side called '" .. word .. "'", 0)
  end
  return list
end

local function check_enabled()
  if not agent_write.enabled() then error("an admin has not turned on the Self-Expanding Blueprints write tools", 0) end
end

-- The asking team's project, or an error the agent reads.
local function own_project(args)
  check_enabled()
  local force = game.forces[args.force]
  local project = force and storage.projects[tonumber(args.id) or 0]
  if not (project and project.force_index == force.index and project.state ~= const.PROJECT_STATE.stopped) then
    error("no such project", 0)
  end
  return project
end

return function(interface)
  interface.seb_pause_project = function(args)
    return { ok = projects.pause(own_project(args)) }
  end

  interface.seb_resume_project = function(args)
    return { ok = projects.resume(own_project(args)) }
  end

  interface.seb_stop_project = function(args)
    projects.stop(own_project(args))
    return { ok = true }
  end

  interface.seb_grow = function(args)
    check_enabled()
    local id, reason = interface.start_project {
      force = args.force, surface = args.surface or "nauvis", design = args.design,
      position = { x = args.x, y = args.y }, max_instances = args.count, directions = sides(args.sides),
    }
    if not id then return { ok = false, reason = reason } end
    return { ok = true, project = id }
  end

  return agent_write
end
