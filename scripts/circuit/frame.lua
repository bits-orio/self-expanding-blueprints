-- A builder's circuit frames: what its input holds (red and green summed),
-- and what its output shows, written into the hidden constant combinator
-- that drives its output connector. Reading the whole input copies every
-- signal on it into Lua, so a builder does that only when it takes a
-- request; every other read asks for the few signals it needs, one by one.

local frame = {}

local INPUT_RED = defines.wire_connector_id.combinator_input_red
local INPUT_GREEN = defines.wire_connector_id.combinator_input_green

-- The input as {virtual = {[name] = count}, item = {...}, fluid = {...}},
-- empty when no wire is connected or nothing is on it, and how many
-- signals were on it.
function frame.read(entity)
  local input = { virtual = {}, item = {}, fluid = {}, entity = {} }
  local signals = entity.get_signals(INPUT_RED, INPUT_GREEN) or {}
  for _, s in ipairs(signals) do
    local kind = s.signal.type or "item"
    local bucket = input[kind]
    if bucket and s.count ~= 0 then bucket[s.signal.name] = (bucket[s.signal.name] or 0) + s.count end
  end
  return input, #signals
end

-- Made once per name: the engine only reads them.
local signal_ids = {}

-- The value of one virtual signal on the input, red and green summed; 0
-- when it is not there.
function frame.signal(entity, name)
  local id = signal_ids[name]
  if not id then
    id = { type = "virtual", name = name }
    signal_ids[name] = id
  end
  return entity.get_signal(id, INPUT_RED, INPUT_GREEN)
end

-- Whether a wire reaches the input at all.
function frame.wired(entity)
  return entity.get_circuit_network(INPUT_RED) ~= nil or entity.get_circuit_network(INPUT_GREEN) ~= nil
end

-- An output as a list of {type, name, count}, in a fixed order so that two
-- equal outputs give equal keys.
local function sorted(values)
  local list = {}
  for key, count in pairs(values) do
    if count ~= 0 then
      local kind, name = key:match("^([^/]+)/(.+)$")
      list[#list + 1] = { type = kind, name = name, count = count }
    end
  end
  table.sort(list, function(a, b) return a.type < b.type or (a.type == b.type and a.name < b.name) end)
  return list
end

local function key_of(list)
  local parts = {}
  for i, s in ipairs(list) do parts[i] = s.type .. "/" .. s.name .. "=" .. s.count end
  return table.concat(parts, ",")
end

-- Shows `values` ({["virtual/seb-ack"] = 5, ["item/iron-plate"] = 20, ...})
-- on the builder's output. Returns the key written, so an unchanged output
-- is not written again.
function frame.write(output, values, last_key)
  local list = sorted(values)
  local key = key_of(list)
  if key == last_key then return key end
  local behavior = output.get_or_create_control_behavior()
  local section = behavior.get_section(1) or behavior.add_section()
  local filters = {}
  for i, s in ipairs(list) do
    filters[i] = { value = { type = s.type, name = s.name, quality = "normal", comparator = "=" }, min = s.count }
  end
  section.filters = filters
  return key
end

return frame
