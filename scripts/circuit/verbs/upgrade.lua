-- Upgrade: order every entity of the builder's force in the rectangle X, Y,
-- W, H upgraded to its next tier (the upgrade a vanilla upgrade planner
-- would pick by default); item signals narrow it to what those items build.
-- DONE once robots have upgraded all of them. With the Cancel signal it
-- cancels those upgrade orders instead (DONE once it has been through the
-- rectangle). A big rectangle is ordered a piece per chunk over a few
-- reads (sweep.lua).

local budget = require("scripts.core.budget")
local answer = require("scripts.circuit.answer")
local sweep = require("scripts.circuit.verbs.sweep")

local upgrade = {}

local MAX_TILES = 512 * 512
local COST = budget.COST

local function wanted(entity, filter)
  if not filter then return true end
  for _, item in pairs(entity.prototype.items_to_place_this or {}) do
    if filter[item.name] then return true end
  end
  return false
end

function upgrade.start(b, request, input)
  local area = answer.area(b, input, MAX_TILES)
  if not area then return answer.fail(b, "invalid") end
  request.filter = next(input.item) and input.item or nil
  request.cancel = input.virtual["seb-cancel"] ~= nil
  request.pending = {}
  sweep.begin(request, area)
  upgrade.tick(b, request)
end

-- One piece: its orders given (or cancelled); returns what that cost.
local function order(b, request, p)
  local force, pending, filter = b.entity.force, request.pending, request.filter
  local found = b.entity.surface.find_entities_filtered { area = sweep.area(p), force = force }
  local ordered = 0
  for _, e in pairs(found) do
    if request.cancel then
      if e.to_be_upgraded() and wanted(e, filter) then
        e.cancel_upgrade(force)
        ordered = ordered + 1
      end
    else
      local next_tier = e.prototype.next_upgrade
      if next_tier and e ~= b.entity and wanted(e, filter) then
        if e.to_be_upgraded() or e.order_upgrade { force = force, target = next_tier.name } then
          pending[#pending + 1] = e
          ordered = ordered + 1
        end
      end
    end
  end
  return #found * COST.check_part + ordered * COST.stamp_part
end

local function waits(e)
  return e.to_be_upgraded()
end

-- Done when none of them waits for its upgrade any more (an upgraded entity
-- is a new one; the old reference is gone).
function upgrade.tick(b, request)
  if not sweep.run(request, b.force_index, function(p) return order(b, request, p) end) then return end
  request.cursor = sweep.first_waiting(request.pending, request.cursor, waits)
  if not request.cursor then answer.done(b) end
end

return upgrade
