-- Copies a team's blueprint builders have stamped that are still being
-- built (storage.stamps_in_flight[force_index]). They count against the
-- team's limit of copies in flight together with its projects' own
-- (gates.force_has_room, D45). The Stamp verb adds each copy it places and
-- takes it off once it is built, lost or given up on, or its request ends.

local loop = require("scripts.core.loop")

local flight = {}

function flight.add(force_index, n)
  local counts = storage.stamps_in_flight or {}
  storage.stamps_in_flight = counts
  local count = math.max(0, (counts[force_index] or 0) + n)
  counts[force_index] = count > 0 and count or nil
  -- A place came free: the team's projects held at its limit try again.
  if n < 0 then loop.wake_force(force_index) end
end

-- The force's index may go to a new force.
function flight.forget(force_index)
  if storage.stamps_in_flight then storage.stamps_in_flight[force_index] = nil end
end

return flight
