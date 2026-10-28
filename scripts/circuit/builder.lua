-- Blueprint builders (DESIGN.md section 4): combinators that take one
-- request at a time on their input and answer on their output.
--   A request is a verb signal whose value is a non-zero request number,
--   held on the input with its parameter signals until the builder answers
--   ACK with that number. The program then drops it and may send the next.
--   The builder answers DONE with the number when the work is finished, or
--   ERR with the number and one named error signal.
-- There is no engine event for a circuit network changing, so builders are
-- read on a short timer that only runs while builders take requests; one
-- with no wire on its input and no request running is looked at once a
-- second.
-- Each read is charged to the builder's team (D44, budget.lua), and a team
-- whose share of server time is used up has its builders read later: when
-- the share is back, or at once when its rate changes (limit_changes.lua).
-- Builders past the team's limit take no requests and are not on the timer:
-- they show the limit error from the moment they start to wait, and a free
-- place or a raised limit lets the oldest in by direct call (roster.lua).
-- Verbs live in scripts/circuit/verbs/.

local const = require("scripts.const")
local scheduler = require("scripts.core.scheduler")
local budget = require("scripts.core.budget")
local frame = require("scripts.circuit.frame")
local answer = require("scripts.circuit.answer")
local verbs = require("scripts.circuit.verbs")
local roster = require("scripts.circuit.roster")
local flight = require("scripts.circuit.flight")

local builder = {}

local NAME = const.BUILDER
local OUTPUT = const.BUILDER_OUTPUT
local READ_TICKS = 12
local IDLE_TICKS = 60
local LIMIT = { [answer.virtual("seb-error-limit")] = 1 }

-- The timer comes back at `tick` (the next read when none is given), unless
-- it is queued for then or sooner. An item queued for later than a new one
-- is stale: storage.builders_due names the live one, and the others do
-- nothing when their time comes.
local function arm(tick)
  tick = tick or game.tick + READ_TICKS
  if storage.builders_due and storage.builders_due <= tick then return end
  storage.builders_due = tick
  scheduler.at(tick, { kind = "builders", due = tick })
end

-- Whether any builder takes requests, and so needs the timer.
local function any_working()
  return next(storage.builders_active) ~= nil
end

-- The hidden combinator that drives the builder's output connector, wired
-- to it with script wires players cannot see or cut. One left on the spot
-- (cloned with the builder, say) goes first: it is unwired and nobody's.
local function attach_output(entity)
  for _, old in pairs(entity.surface.find_entities_filtered { name = OUTPUT, position = entity.position, radius = 0.5 }) do
    old.destroy()
  end
  local output = entity.surface.create_entity {
    name = OUTPUT, position = entity.position, force = entity.force, create_build_effect_smoke = false,
  }
  for _, color in ipairs({ "red", "green" }) do
    local from = entity.get_wire_connector(defines.wire_connector_id["combinator_output_" .. color], true)
    local to = output.get_wire_connector(defines.wire_connector_id["circuit_" .. color], true)
    from.connect_to(to, false, defines.wire_origin.script)
  end
  return output
end

-- The ids now of the builders in `set` (every builder, or the working
-- ones): reading one may raise events that add or remove builders, and a
-- table must not gain keys while it is walked.
local function ids_of(set)
  local list = {}
  for id in pairs(set) do list[#list + 1] = id end
  return list
end

-- The builder's output combinator, made again if it was lost.
local function output_of(b)
  if not b.output.valid then b.output, b.output_key = attach_output(b.entity), nil end
  return b.output
end

-- A builder past the team's limit shows the limit error from the moment it
-- starts to wait, written once: nothing looks at it again until it is let in.
local function show_limit(b)
  b.output_key = frame.write(output_of(b), LIMIT, b.output_key)
end
roster.hooks.waiting = show_limit

function builder.add(entity)
  if not (entity and entity.valid and entity.name == NAME) then return end
  local id = entity.unit_number
  if storage.builders[id] then return end
  roster.ensure()
  local behavior = entity.get_control_behavior()
  if behavior then behavior.parameters = nil end
  local b = {
    id = id, entity = entity, output = attach_output(entity), answer = {},
    force_index = entity.force_index, surface_index = entity.surface_index,
  }
  storage.builders[id] = b
  storage.builder_regs[script.register_on_object_destroyed(entity)] = id
  roster.join(b)
  if not b.waiting then arm() end
end

-- `dropping`: its whole force is going, so nobody takes its place.
function builder.remove(id, dropping)
  local b = storage.builders[id]
  if not b then return end
  roster.ensure()
  verbs.drop(b)
  if b.output and b.output.valid then b.output.destroy() end
  storage.builders[id] = nil
  roster.leave(b, dropping)
  if not dropping and any_working() then arm() end
end

-- A place came free or the limit rose (set_limits): the oldest waiting
-- builders of the force (or of every force) take the places, and the timer
-- looks at them.
function builder.rebalance(force_index)
  roster.ensure()
  local let_in
  if force_index then let_in = roster.rebalance(force_index) else let_in = roster.rebalance_all() end
  if let_in then arm() end
end

-- The rate of a team's share of server time changed (a map setting, or
-- set_limits; no force: every team's). Builders told to wait for the old
-- rate are looked at again at once.
function builder.rate_changed(force_index)
  roster.ensure()
  for id in pairs(storage.builders_active) do
    local b = storage.builders[id]
    if b and (not force_index or b.force_index == force_index) then b.next_read = nil end
  end
  if any_working() then arm(game.tick + 1) end
end

-- A builder whose entity now belongs to another force (a merge, a script)
-- starts afresh as that force's.
local function rehome(b, dropping)
  verbs.drop(b)
  roster.leave(b, dropping)
  b.force_index = b.entity.force_index
  if b.output.valid then b.output.force = b.entity.force end
  roster.join(b)
  if not b.waiting then b.next_read = nil end
end

-- A force merged or released: its builders' requests end with its records.
-- One still standing under another force (merged into it) carries on as
-- that force's builder; the rest go. Copies counted in flight for the
-- force go with it, as a new force may get its index.
function builder.drop_force(force_index)
  roster.ensure()
  for _, id in ipairs(ids_of(storage.builders)) do
    local b = storage.builders[id]
    if b and b.force_index == force_index then
      if b.entity.valid and b.entity.force_index ~= force_index then rehome(b, true) else builder.remove(id, true) end
    end
  end
  roster.forget_force(force_index)
  flight.forget(force_index)
  if any_working() then arm() end
end

-- The builders of a deleted surface go as a batch; the forces that lost
-- some then let their oldest waiting builders in, once.
function builder.drop_surface(surface_index)
  roster.ensure()
  local forces = {}
  for _, id in ipairs(ids_of(storage.builders)) do
    local b = storage.builders[id]
    if b and b.surface_index == surface_index then
      forces[b.force_index] = true
      builder.remove(id, true)
    end
  end
  for force_index in pairs(forces) do
    roster.compact(force_index)
    roster.rebalance(force_index)
  end
  if any_working() then arm() end
end

-- on_object_destroyed. A builder that is part of a copy is registered by
-- the copy too (same registration number), so this never claims the event.
function builder.on_object_destroyed(event)
  local id = storage.builder_regs[event.registration_number]
  if not id then return end
  storage.builder_regs[event.registration_number] = nil
  builder.remove(id)
end

-- Every build path that can make a builder (placed, built by robots,
-- revived, cloned, built on a platform).
function builder.on_built(event)
  builder.add(event.entity or event.destination)
end

-- A builder's own decider settings stay empty: settings copied onto it from
-- a real decider, or pasted with a blueprint, would add to its answers.
local function clear_settings(entity)
  if not (entity and entity.valid and entity.name == NAME) then return end
  local behavior = entity.get_control_behavior()
  if behavior then behavior.parameters = nil end
end

function builder.on_entity_settings_pasted(event)
  clear_settings(event.destination)
end

function builder.on_blueprint_settings_pasted(event)
  clear_settings(event.entity)
end

-- The output a builder shows: its answer, plus what its verb reports now.
local function show(b)
  local values = {}
  for key, count in pairs(b.answer.values or {}) do values[key] = count end
  verbs.report(b, values)
  b.output_key = frame.write(b.output, values, b.output_key)
end

local function read_one(b, now)
  if not (verbs.busy(b) or frame.wired(b.entity)) then
    b.next_read = now + IDLE_TICKS
    return
  end
  b.next_read = now + READ_TICKS
  verbs.step(b, b.entity)
  show(b)
end

-- One builder that is due. The read is charged once it is done, so a team
-- with any time left always gets some work out of it.
local function visit(b, now)
  output_of(b)
  if b.entity.force_index ~= b.force_index then rehome(b) end
  -- One sent back to wait shows the limit error and is not looked at again.
  if roster.waits(b, verbs.busy(b)) then return end
  local force_index = b.force_index
  if not budget.ready(force_index) then
    b.next_read = now + budget.wait(force_index)
    return
  end
  read_one(b, now)
  budget.charge(force_index, budget.COST.builder_read)
end

-- Reads every builder that is due; the timer comes back for the soonest.
scheduler.register("builders", function(item, now)
  if item.due ~= storage.builders_due then return end
  storage.builders_due = nil
  roster.ensure()
  -- A raised limit lets waiting builders in here, whoever changed it (a
  -- script raises no setting event): one look per force, not per builder.
  roster.rebalance_all()
  local soonest
  for _, id in ipairs(ids_of(storage.builders_active)) do
    local b = storage.builders[id]
    if b and not b.entity.valid then
      builder.remove(id)
    elseif b then
      if (b.next_read or 0) <= now then visit(b, now) end
      -- One let in by a builder that went has no next read: it is due now.
      if not b.waiting then soonest = math.min(soonest or math.huge, b.next_read or now + 1) end
    end
  end
  if soonest then arm(soonest) end
end)

return builder
