-- Logging helpers. Every line carries the tick and a global sequence number,
-- so event order inside one tick is visible.
local M = {}

function M.ser(v)
  return serpent.line(v, {comment = false, nocode = true})
end

local function next_seq()
  storage.seq = (storage.seq or 0) + 1
  return storage.seq
end
M.next_seq = next_seq

function M.out(msg)
  local seq = next_seq()
  log("SEB_SPIKE t=" .. game.tick .. " s=" .. seq .. " " .. msg)
  return seq
end

function M.verdict(q, name, ok, details)
  M.out("VERDICT " .. q .. " " .. name .. " " .. (ok and "PASS" or "FAIL")
    .. (details and (" " .. details) or ""))
end

-- An observed fact rather than an expectation.
function M.answer(q, name, value, details)
  M.out("ANSWER " .. q .. " " .. name .. "=" .. tostring(value) .. (details and (" " .. details) or ""))
end

-- Reading unit_number, returning the value or the error text.
function M.unit(e)
  local ok, unit = pcall(function() return e.unit_number end)
  if ok then return unit, nil end
  return nil, tostring(unit)
end

-- Profiler lines have to go through a localised string.
function M.cost(label, profiler)
  local seq = next_seq()
  log({"", "SEB_SPIKE t=" .. game.tick .. " s=" .. seq .. " " .. label .. " ", profiler})
end

function M.pos(p)
  if not p then return "nil" end
  return string.format("%g,%g", p.x or p[1], p.y or p[2])
end

function M.ent(e)
  if not e then return "nil" end
  if not e.valid then return "invalid" end
  local name = e.name
  if e.type == "entity-ghost" or e.type == "tile-ghost" then
    name = e.name .. "/" .. e.ghost_name
  end
  local unit, err = M.unit(e)
  return name .. "#" .. (err and "unit_err" or tostring(unit)) .. "@" .. M.pos(e.position)
end

return M
