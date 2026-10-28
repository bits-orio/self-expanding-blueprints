-- Dry runs: a project that plans instead of stamping (DESIGN.md "Seeing the
-- plan"). Every spot that passes the checks becomes a planned copy, a
-- footprint and its sockets with no entities, which counts as finished at
-- once, so the whole plan unfolds as outlines before any ghost exists.
-- Planned copies live in their project and block only that plan.

local geometry = require("scripts.core.geometry")
local placement = require("scripts.core.placement")

local plan = {}

-- A plan stops here even without a count, so a fill of open land cannot
-- grow without end.
plan.LIMIT = 400

-- The planned copy with this id (a string, never an instance number).
function plan.get(project, id)
  return project.planned and project.planned[id]
end

-- The id of a planned copy `box` overlaps, or nil.
function plan.overlaps(project, box)
  local seen, hit = {}, nil
  geometry.each_chunk(box, function(cx, cy)
    if hit then return end
    for _, id in ipairs(project.plan_chunks[geometry.chunk_key(cx, cy)] or {}) do
      if not seen[id] then
        seen[id] = true
        if geometry.overlaps(project.planned[id].footprint, box) then
          hit = id
          return
        end
      end
    end
  end)
  return hit
end

local function index(project, copy)
  geometry.each_chunk(copy.footprint, function(cx, cy)
    local key = geometry.chunk_key(cx, cy)
    local list = project.plan_chunks[key] or {}
    project.plan_chunks[key] = list
    list[#list + 1] = copy.id
  end)
end

-- Files a spot that passed every check as a planned copy and returns it.
-- It has what frontier.open and the placement of children read.
function plan.add(project, p)
  project.plan_count = (project.plan_count or 0) + 1
  local copy = {
    id = "p" .. project.plan_count, planned = true, design_id = p.design.id, version = p.design.version,
    position = p.position, direction = p.direction, footprint = p.footprint,
    repeat_size = placement.repeat_size(p.prepared, p.direction),
    sockets = placement.sockets(p.prepared, p.position, p.direction),
  }
  project.planned[copy.id] = copy
  index(project, copy)
  return copy
end

function plan.count(project)
  return project.plan_count or 0
end

return plan
