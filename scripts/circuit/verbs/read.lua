-- Read: what the port of the copy in the Instance signal holds (a constant
-- combinator's settings; a decider's or arithmetic combinator's output),
-- shown with DONE.

local answer = require("scripts.circuit.answer")
local port = require("scripts.circuit.verbs.port")

local read = {}

local W = defines.wire_connector_id

local function wires_of(entity)
  if entity.type == "constant-combinator" then return W.circuit_red, W.circuit_green end
  return W.combinator_output_red, W.combinator_output_green
end

local function add(values, kind, name, count)
  local key = (kind or "item") .. "/" .. name
  values[key] = answer.clamp((values[key] or 0) + count)
end

-- A constant combinator's own settings: what it holds even with no wire on it.
local function held(entity, values)
  local behavior = entity.get_control_behavior()
  for _, section in pairs(behavior and behavior.sections or {}) do
    if section.active ~= false then
      for _, filter in pairs(section.filters or {}) do
        if filter.value and filter.value.name then add(values, filter.value.type, filter.value.name, filter.min or 0) end
      end
    end
  end
end

function read.start(b, request, input)
  local entity, why = port.of(b, input)
  if not entity then return answer.fail(b, why) end
  local values = {}
  if entity.type == "constant-combinator" then
    held(entity, values)
  else
    for _, s in ipairs(entity.get_signals(wires_of(entity)) or {}) do add(values, s.signal.type, s.signal.name, s.count) end
  end
  answer.done(b, values)
end

return read
