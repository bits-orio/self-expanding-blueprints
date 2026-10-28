-- Clear: order deconstruction of everything in the rectangle X, Y, W, H
-- that belongs to the builder's force, trees and rocks included; item
-- signals narrow it to what those items place. DONE when all of it is gone.
-- With the Cancel signal it cancels those orders instead (DONE once it has
-- been through the rectangle). A big rectangle is ordered a piece per chunk
-- over a few reads (sweep.lua).

local budget = require("scripts.core.budget")
local clearing = require("scripts.core.clearing")
local answer = require("scripts.circuit.answer")
local sweep = require("scripts.circuit.verbs.sweep")

local clear = {}

local MAX_TILES = 512 * 512

function clear.start(b, request, input)
  local area = answer.area(b, input, MAX_TILES)
  if not area then return answer.fail(b, "invalid") end
  request.filter = next(input.item) and input.item or nil
  request.cancel = input.virtual["seb-cancel"] ~= nil
  request.pending = {}
  sweep.begin(request, area)
  clear.tick(b, request)
end

-- One piece: its orders given (or cancelled); returns what that cost.
local function order(b, request, p)
  local ordered = clearing.run {
    surface = b.entity.surface, force = b.entity.force, box = sweep.area(p), filter = request.filter,
    cancel = request.cancel, skip = { [b.entity.unit_number] = true, [b.output.unit_number or -1] = true },
  }
  local pending = request.pending
  for _, e in ipairs(ordered) do pending[#pending + 1] = e end
  return #ordered * budget.COST.stamp_part
end

local function waits(e)
  return e.to_be_deconstructed()
end

-- Done when nothing it ordered still waits for the robots: an order
-- cancelled by anyone ends that entity's wait as well as its removal.
function clear.tick(b, request)
  if not sweep.run(request, b.force_index, function(p) return order(b, request, p) end) then return end
  request.cursor = sweep.first_waiting(request.pending, request.cursor, waits)
  if not request.cursor then answer.done(b) end
end

return clear
