-- Stamp: copies of a design at X, Y (relative to the builder unless
-- Absolute), turned by Rotation; Superforce marks buildings in the way for
-- removal. Grid X and Grid Y stamp a grid of copies, Spacing tiles apart
-- (default 0: edge to edge, at most 1000). ACK at once; DONE with the first
-- copy's number once robots have built every copy, ERR if none could be
-- placed, one comes out incomplete, or one stalls where no robots reach
-- (out of range) or for items the network does not have (materials).
-- The copies go down one by one, over as many reads as the team's share
-- of server time and its limit of copies in flight take (D44, D45); a
-- point where none fits is skipped. Each copy counts in flight
-- (flight.lua) until it is built, lost or given up on, or the request ends.

local const = require("scripts.const")
local growth = require("scripts.core.growth")
local placement = require("scripts.core.placement")
local gates = require("scripts.core.gates")
local budget = require("scripts.core.budget")
local work = require("scripts.core.work")
local limits = require("scripts.core.limits")
local answer = require("scripts.circuit.answer")
local flight = require("scripts.circuit.flight")
local design_of = require("scripts.circuit.verbs.design_of")

local stamp = {}

local STATE = const.STATE
local INSTANCE = answer.virtual("seb-instance")
local BUILT = answer.virtual("seb-built")
local GHOSTS_LEFT = answer.virtual("seb-ghosts-left")
local MAX_GRID = 16
local MAX_SPACING = 1000
-- Stall reasons that end the wait: nothing will change them by itself.
local GIVES_UP = { [const.REASON.no_network] = true, [const.REASON.missing_materials] = true }

local function count(input, name)
  return math.max(1, math.min(MAX_GRID, input.virtual[name] or 1))
end

-- The grid's step: the copy's footprint, turned, plus the spacing.
local function steps(prepared, direction, spacing)
  local box = placement.footprint(prepared, { x = 0, y = 0 }, direction)
  return box.right - box.left + spacing, box.bottom - box.top + spacing
end

function stamp.start(b, request, input)
  local design = design_of(b, input)
  if not (design and design.prepared and design.prepared.ok) then return answer.fail(b, "unknown-design") end
  local direction = answer.direction(input)
  local base = answer.target(b, input)
  local spacing = input.virtual["seb-spacing"] or 0
  if not base or spacing > MAX_SPACING then return answer.fail(b, "invalid") end
  local dx, dy = steps(design.prepared, direction, math.max(0, spacing))
  request.ctx = {
    force_index = b.force_index, surface_index = b.entity.surface_index, design_id = design.id,
    charted_only = limits.of(b.force_index, "builders_charted_only"), generate = false,
    materials = false, superforce = input.virtual["seb-superforce"] ~= nil,
  }
  request.grid = {
    x = base.x, y = base.y, dx = dx, dy = dy, direction = direction,
    columns = count(input, "seb-grid-x"), cells = count(input, "seb-grid-x") * count(input, "seb-grid-y"),
  }
  request.tried, request.instance_ids, request.flying = 0, {}, {}
  stamp.tick(b, request)
end

local function land(request, id)
  if not request.flying[id] then return end
  request.flying[id] = nil
  flight.add(request.ctx.force_index, -1)
end

-- One grid point (the next not tried): a copy or a refusal, charged as the
-- growth loop charges a step, for the work it did (work.lua).
local function try_next(request)
  local grid, ctx = request.grid, request.ctx
  local i, j = request.tried % grid.columns, math.floor(request.tried / grid.columns)
  local point = { x = grid.x + i * grid.dx, y = grid.y + j * grid.dy }
  if not answer.on_map(point) then return { reason = "invalid" } end
  local result = growth.stamp_once(ctx, { position = point }, grid.direction)
  work.charge(ctx.force_index, result.work)
  return result
end

-- Places copies at the points not tried yet while the team may work and
-- has room for another copy in flight.
local function place(request)
  local force_index = request.ctx.force_index
  while request.tried < request.grid.cells do
    if not (budget.ready(force_index) and gates.force_has_room(force_index)) then return end
    local result = try_next(request)
    request.tried = request.tried + 1
    if result.kind == "stamped" then
      local id = result.instance.id
      request.instance_ids[#request.instance_ids + 1] = id
      request.flying[id] = true
      flight.add(force_index, 1)
    else
      request.first_failure = request.first_failure or result.reason
    end
  end
end

-- Why a copy fails its request: lost, incomplete, or stalled for good.
local function failure_of(instance)
  local state = instance and instance.state
  if not state or state == STATE.incomplete or state == STATE.retiring or state == STATE.retired then
    return "incomplete"
  end
  if state == STATE.stalled and GIVES_UP[instance.reason] then return instance.reason end
end

-- The copies placed so far: one no longer building is off the count in
-- flight. Returns why the request fails, if it does (the first copy that
-- fails it), and whether every copy is built.
local function settle(request)
  local failure, built = nil, true
  for _, id in ipairs(request.instance_ids) do
    local instance = storage.instances[id]
    local state = instance and instance.state
    if request.flying and state ~= STATE.building and state ~= STATE.stalled then land(request, id) end
    failure = failure or failure_of(instance)
    built = built and state == STATE.complete
  end
  return failure, built
end

-- Done when every point is tried and every copy built; a copy lost,
-- incomplete or stalled for good fails it. A request taken before copies
-- went down one by one has all of its copies placed and none in flight.
function stamp.tick(b, request)
  local ids = request.instance_ids
  local failure, built = settle(request)
  if failure then return answer.fail(b, failure, { [INSTANCE] = ids[1] }) end
  local placed = #ids
  if request.grid then place(request) end
  if request.grid and request.tried < request.grid.cells then return end
  if #ids == 0 then return answer.fail(b, request.first_failure) end
  if built and #ids == placed then answer.done(b, { [INSTANCE] = ids[1], [BUILT] = #ids }) end
end

function stamp.release(b, request)
  for id in pairs(request.flying or {}) do land(request, id) end
end

function stamp.report(b, request, values)
  local ids = request.instance_ids
  if not (ids and ids[1]) then return end
  values[INSTANCE] = ids[1]
  if request.finished then return end
  local left = 0
  for _, id in ipairs(ids) do
    local instance = storage.instances[id]
    left = left + (instance and instance.ghosts_left or 0)
  end
  values[GHOSTS_LEFT] = left
end

return stamp
