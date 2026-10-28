-- Grow: start a project from X, Y with a design, turned by Rotation; the
-- Grow north/east/south/west signals choose the sides a plain design grows
-- toward (default east and south), Count stops it after that many copies.
-- ACK at once; DONE when the project finishes (or when Stop is on the
-- input, which stops it: grow.stop). While it runs the builder shows its status:
-- ghosts left, open sockets, blocked sockets, copies built, and the next
-- copy's bill of materials as item signals (grow_report.lua). Pause on the
-- input pauses it for as long as it is there. Running out of the team's
-- share of server time never reaches Grow: the builder is not read until
-- the share is back (builder.lua).

local const = require("scripts.const")
local geometry = require("scripts.core.geometry")
local projects = require("scripts.core.projects")
local limits = require("scripts.core.limits")
local answer = require("scripts.circuit.answer")
local design_of = require("scripts.circuit.verbs.design_of")
local grow_report = require("scripts.circuit.verbs.grow_report")

local grow = {}

-- What a running Grow looks at on the input (verbs.lua).
grow.CONTROLS = { "seb-pause" }

local STATE = const.PROJECT_STATE
local SIDES = {
  { "seb-grow-north", geometry.NORTH }, { "seb-grow-east", geometry.EAST },
  { "seb-grow-south", geometry.SOUTH }, { "seb-grow-west", geometry.WEST },
}

local function sides(input)
  local list = {}
  for _, side in ipairs(SIDES) do
    if input.virtual[side[1]] then list[#list + 1] = side[2] end
  end
  return #list > 0 and list or nil
end

function grow.start(b, request, input)
  local design = design_of(b, input)
  if not design then return answer.fail(b, "unknown-design") end
  local position = answer.target(b, input)
  if not position then return answer.fail(b, "invalid") end
  local count = input.virtual["seb-count"]
  local project, reason = projects.start {
    force_index = b.force_index, surface_index = b.entity.surface_index, design_id = design.id,
    position = position, direction = answer.direction(input), directions = sides(input),
    max_instances = count and count > 0 and count or nil,
    -- Never map the game has not made yet (D43); charted land only unless
    -- the map setting allows any generated land.
    charted_only = limits.of(b.force_index, "builders_charted_only"), generate = false,
    superforce = input.virtual["seb-superforce"] ~= nil,
  }
  if not project then return answer.fail(b, reason) end
  request.project_id = project.id
end

-- Stop ends a growth project for good: that is how it is meant to end.
function grow.stop(b, request)
  local project = storage.projects[request.project_id]
  if project and project.state ~= STATE.stopped then projects.stop(project) end
  answer.done(b)
end

function grow.tick(b, request, input)
  local project = storage.projects[request.project_id]
  if not project or project.state == STATE.stopped then return answer.done(b) end
  local pause = input.virtual["seb-pause"] ~= nil
  if pause and project.state == STATE.growing then
    request.paused = projects.pause(project)
  elseif not pause and request.paused and project.state == STATE.paused then
    request.paused = not projects.resume(project)
  end
  if project.state == STATE.finished then return answer.done(b) end
end

-- What it shows while it runs, and once it has ended (grow_report.lua).
grow.report = grow_report.show

return grow
