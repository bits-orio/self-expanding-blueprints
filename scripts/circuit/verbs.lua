-- Requests on a builder's input and the answers on its output. One request
-- runs at a time: while one runs, the next is not acknowledged, and its
-- program keeps holding it. A request's DONE or ERR stays on the output for
-- at least one read before the next request is taken. Stop on the input
-- ends whatever runs: ERR "stopped", leaving what it started (ghosts,
-- orders) to the robots. A read looks only at the verb signals, or while a
-- request runs at Stop and the signals its verb follows; the whole input is
-- read once, when a request is taken (frame.lua). Each verb module has
--   start(b, request, input)    accept it: begin the work, or finish at once
--   tick(b, request, controls)  optional, every read while it runs
--   CONTROLS                    optional, the signals tick looks at (as
--                               {virtual = {[name] = value}})
--   stop(b, request)            optional, what Stop does instead
--   report(b, request, values)  optional, what it shows on the output now
--   release(b, request)         optional, gives back what the request holds
--                               once it ends or its builder goes
-- and ends a request through answer.done or answer.fail.

local budget = require("scripts.core.budget")
local answer = require("scripts.circuit.answer")
local frame = require("scripts.circuit.frame")

local verbs = {}

local VERBS = { "stamp", "grow", "remove", "clear", "sense", "capture", "upgrade", "find", "read", "write" }

local handlers, ORDER = {}, {}
for i, verb in ipairs(VERBS) do
  handlers[verb] = require("scripts.circuit.verbs." .. verb)
  ORDER[i] = { "seb-" .. verb, verb }
end

local STOP = "seb-stop"

-- The request on the input, or nil. Two verbs at once is not a request the
-- builder can serve: it answers ERR "invalid" for the first one's number.
local function requested(entity)
  local found
  for _, entry in ipairs(ORDER) do
    local n = frame.signal(entity, entry[1])
    if n ~= 0 then
      if found then return { verb = found.verb, number = found.number, invalid = true } end
      found = { verb = entry[2], number = n }
    end
  end
  return found
end

local function controls(entity, handler)
  local values = {}
  for _, name in ipairs(handler.CONTROLS or {}) do
    local n = frame.signal(entity, name)
    if n ~= 0 then values[name] = n end
  end
  return { virtual = values }
end

-- At most once per request, whichever way it ends.
local function release(b)
  local request = b.request
  if not request or request.released then return end
  request.released = true
  local handler = handlers[request.verb]
  if handler.release then handler.release(b, request) end
end

local function stop(b)
  answer.fail(b, "stopped")
end

-- Works on the running request; true while one ran this read (finished
-- now or not), so the next request waits for the following read.
local function work(b, entity)
  local current = b.request
  if not current or current.finished then return false end
  local handler = handlers[current.verb]
  if frame.signal(entity, STOP) ~= 0 then
    (handler.stop or stop)(b, current)
  elseif handler.tick then
    handler.tick(b, current, controls(entity, handler))
  end
  return true
end

local function take(b, entity)
  local req = requested(entity)
  if not req or req.number == b.last_number then return end
  b.last_number = req.number
  b.request = { verb = req.verb, number = req.number }
  b.answer = { values = { [answer.virtual("seb-ack")] = req.number } }
  if req.invalid then return answer.fail(b, "invalid") end
  -- A wire carrying thousands of signals costs its team by its size.
  local input, signals = frame.read(entity)
  budget.charge(b.force_index, signals * budget.COST.input_signal)
  handlers[req.verb].start(b, b.request, input)
end

-- Whether a request is running, so its builder must be read again soon.
function verbs.busy(b)
  return b.request ~= nil and not b.request.finished
end

function verbs.step(b, entity)
  if not work(b, entity) then take(b, entity) end
  if b.request and b.request.finished then release(b) end
end

-- The builder goes, or starts afresh under another force: its request ends
-- unanswered, giving back what it holds, and a request still on its input
-- counts as new.
function verbs.drop(b)
  release(b)
  b.request, b.answer, b.last_number = nil, {}, nil
end

function verbs.report(b, values)
  local request = b.request
  local handler = request and handlers[request.verb]
  if handler and handler.report then handler.report(b, request, values) end
end

return verbs
