-- What every verb needs: ending a request with DONE or ERR, the named error
-- for a refusal reason, and reading where and how a request points (X, Y,
-- W, H, Rotation, Absolute).

local const = require("scripts.const")

local answer = {}

-- Named error signals for the reasons a request can fail.
local ERROR_OF = {
  [const.REASON.water] = "water", [const.REASON.cliff] = "cliff", [const.REASON.building] = "building",
  [const.REASON.joined] = "building", [const.REASON.overlaps_parent] = "building",
  [const.REASON.uncharted] = "uncharted", [const.REASON.chunks] = "uncharted",
  [const.REASON.missing_materials] = "materials", [const.REASON.unknown_design] = "unknown-design",
  [const.REASON.invalid_design] = "unknown-design", [const.REASON.no_network] = "out-of-range",
  [const.REASON.no_resource] = "no-resource", [const.REASON.probe] = "probe",
  [const.REASON.ghost_removed] = "incomplete", [const.REASON.held_land] = "held-land",
  [const.REASON.stamp_short] = "building",
  -- The map's limits for the team (D45): one error says the team is at one.
  [const.REASON.too_many_projects] = "limit", [const.REASON.too_many_designs] = "limit",
  [const.REASON.design_too_big] = "limit", [const.REASON.too_many_sockets] = "limit",
  [const.REASON.too_many_poles] = "limit",
}

-- The engine makes no map beyond +-1,000,000 tiles and throws on positions
-- far past it, so a request pointing outside is refused before any lookup.
local MAP_LIMIT = 1000000

local function inside(n)
  return n >= -MAP_LIMIT and n <= MAP_LIMIT
end

function answer.on_map(point)
  return inside(point.x) and inside(point.y)
end

function answer.virtual(name)
  return "virtual/" .. name
end
local virtual = answer.virtual

local function error_signal(error)
  local name = ERROR_OF[error] or error
  if prototypes.virtual_signal["seb-error-" .. name] then return "seb-error-" .. name end
  return "seb-error-invalid"
end

local function finish(b, values, extra)
  b.request.finished = true
  for k, v in pairs(extra or {}) do values[k] = v end
  b.answer = { values = values }
end

function answer.done(b, extra)
  local n = b.request.number
  finish(b, { [virtual("seb-ack")] = n, [virtual("seb-done")] = n }, extra)
end

-- `error` is a named error ("water", "not-found", ...) or a refusal reason.
function answer.fail(b, error, extra)
  local n = b.request.number
  finish(b, { [virtual("seb-ack")] = n, [virtual("seb-error")] = n, [virtual(error_signal(error))] = 1 }, extra)
end

-- Where X and Y point: a tile relative to the builder, or the map tile
-- itself when the Absolute signal is set. Returns the tile's centre, or nil
-- when it is off the map.
function answer.target(b, input)
  local x, y = input.virtual["signal-X"] or 0, input.virtual["signal-Y"] or 0
  if not input.virtual["seb-absolute"] then
    local p = b.entity.position
    x, y = math.floor(p.x) + x, math.floor(p.y) + y
  end
  local point = { x = x + 0.5, y = y + 0.5 }
  if answer.on_map(point) then return point end
end

-- The rectangle X, Y, W, H: top-left corner and size, at least 1 x 1. Nil
-- when it leaves the map or covers more than `max_tiles`.
function answer.area(b, input, max_tiles)
  local corner = answer.target(b, input)
  if not corner then return nil end
  local w, h = math.max(1, input.virtual["signal-W"] or 1), math.max(1, input.virtual["signal-H"] or 1)
  local left, top = corner.x - 0.5, corner.y - 0.5
  local box = { left = left, top = top, right = left + w, bottom = top + h }
  if w * h > max_tiles or not answer.on_map({ x = box.right, y = box.bottom }) then return nil end
  return box
end

-- The quarter turns clockwise in the Rotation signal, as a direction.
function answer.direction(input)
  return ((input.virtual["signal-R"] or 0) % 4) * 4
end

-- Signal values are 32-bit.
function answer.clamp(n)
  return math.max(-2147483648, math.min(2147483647, math.floor(n)))
end

return answer
