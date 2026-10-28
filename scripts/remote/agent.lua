-- Read tools for AI Agent Bridge (DESIGN.md section 6): the bridge scans
-- every remote interface for a zero-argument agent_tools_v1 and offers the
-- tools it lists to its agent, so a player can ask "why is my solar field
-- stuck?" in chat. Each tool takes one table (the bridge adds `force`) and
-- returns plain data. Read only: nothing here changes the game; the write
-- tools (agent_write.lua) join the list only while an admin allows them.

local library = require("scripts.core.library")
local projects = require("scripts.core.projects")
local status = require("scripts.core.status")
local history = require("scripts.core.history")

local MANIFEST = {
  seb_projects = {
    desc = "Self-Expanding Blueprints: the team's growth projects, each with its design, copies built and building, "
      .. "and its status (growing, waiting, stalled, paused, finished, or planning/planned for a dry run) with "
      .. "the reason it waits or stalled.",
  },
  seb_project = {
    desc = "Self-Expanding Blueprints: one growth project in detail: status and reason, counts, closed sockets by "
      .. "reason, and its recent history (blocks, waits, stalls, pauses).",
    params = { id = "integer! the project number from seb_projects" },
  },
  seb_designs = {
    desc = "Self-Expanding Blueprints: the team's designs: number, name, version, size in tiles and how each grows.",
  },
}

local function force_index(args)
  local force = type(args) == "table" and args.force and game.forces[args.force]
  return force and force.index
end

local function design_name(project)
  local design = library.get(project.force_index, project.design_id)
  return design and design.name or "?"
end

local function row(project)
  return {
    id = project.id, design = design_name(project), state = project.state, status = status.of(project),
    built = project.count - project.building, building = project.building,
    spots_to_try = #project.frontier + #project.parked,
  }
end

return function(interface)
  local write = require("scripts.remote.agent_write")(interface)

  interface.agent_tools_v1 = function()
    if not write.enabled() then return { v = 1, tools = MANIFEST } end
    local tools = {}
    for name, tool in pairs(MANIFEST) do tools[name] = tool end
    for name, tool in pairs(write.MANIFEST) do tools[name] = tool end
    return { v = 1, tools = tools }
  end

  interface.seb_projects = function(args)
    local index = force_index(args)
    local rows = {}
    for _, project in ipairs(index and projects.list(index) or {}) do
      if project.state ~= "stopped" then rows[#rows + 1] = row(project) end
    end
    return { projects = rows }
  end

  interface.seb_project = function(args)
    local index = force_index(args)
    local project = index and storage.projects[type(args) == "table" and args.id or 0]
    if not (project and project.force_index == index) then return { error = "no such project" } end
    local out = projects.summary(project)
    out.design = design_name(project)
    out.history = history.copy(project)
    return out
  end

  interface.seb_designs = function(args)
    local index = force_index(args)
    local rows = {}
    for _, design in ipairs(index and library.list(index) or {}) do
      local prepared = design.prepared or {}
      local b = prepared.bounds
      rows[#rows + 1] = {
        id = design.id, name = design.name, version = design.version, ok = prepared.ok == true,
        width = b and (b.right - b.left), height = b and (b.bottom - b.top),
        sockets = prepared.sockets and #prepared.sockets or 0, plug = prepared.entry ~= nil,
      }
    end
    return { designs = rows }
  end
end
