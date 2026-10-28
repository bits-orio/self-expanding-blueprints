-- Logging helpers. Every observation goes out as one "SEB_SPIKE ..." line.
local M = {}

function M.n(v)
  if type(v) ~= "number" then return tostring(v) end
  return string.format("%.10g", v)
end

function M.p(pos)
  if not pos then return "nil" end
  return M.n(pos.x) .. "," .. M.n(pos.y)
end

function M.box(b)
  if not b then return "nil" end
  return "[" .. M.n(b.l) .. "," .. M.n(b.t) .. ".." .. M.n(b.r) .. "," .. M.n(b.b) .. "]"
end

function M.out(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
  log("SEB_SPIKE " .. table.concat(parts, " "))
end

function M.verdict(id, ok, ...)
  M.out(id, ok and "PASS" or "FAIL", ...)
end

function M.line(t)
  return serpent.line(t, {comment = false})
end

function M.bits(list)
  local s = {}
  for i, v in ipairs(list) do s[i] = v and "1" or "0" end
  return table.concat(s)
end

return M
