-- Write: the data signals on the builder's input become what the port of
-- the copy in the Instance signal holds (its port must be a constant
-- combinator). Data signals are every signal except the request's own:
-- the verb, its inputs and the mod's other signals.

local answer = require("scripts.circuit.answer")
local port = require("scripts.circuit.verbs.port")

local write = {}

local CONTROL = { ["signal-X"] = true, ["signal-Y"] = true, ["signal-W"] = true, ["signal-H"] = true, ["signal-R"] = true }

local function data_filters(input)
  local filters = {}
  for kind, bucket in pairs(input) do
    for name, count in pairs(bucket) do
      local ours = kind == "virtual" and (name:sub(1, 4) == "seb-" or CONTROL[name])
      if not ours then
        filters[#filters + 1] = { value = { type = kind, name = name, quality = "normal", comparator = "=" }, min = count }
      end
    end
  end
  table.sort(filters, function(a, c) return a.value.type .. a.value.name < c.value.type .. c.value.name end)
  return filters
end

function write.start(b, request, input)
  local entity, why = port.of(b, input)
  if not entity then return answer.fail(b, why) end
  if entity.type ~= "constant-combinator" then return answer.fail(b, "invalid") end
  local behavior = entity.get_or_create_control_behavior()
  local section = behavior.get_section(1) or behavior.add_section()
  section.filters = data_filters(input)
  answer.done(b)
end

return write
