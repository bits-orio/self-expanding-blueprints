-- What trying a design at a spot did, and what that costs its force (D44):
-- the one estimate for growth steps, plans, the builder's Find and Stamp,
-- and a plan's look-only ghosts. A record counts
--   spots    designs tried at a spot: placement, rules, preview room and
--            the fixed part of the terrain walk
--   chunks   footprint chunks a check walked, once for each walk
--   probes   probes looked at, one engine count each
--   checked  parts and Keep clear tiles the obstacle check looked at, its
--            looks for water under parts (two where it found some), and
--            lines of the cost the materials gate looked up
--   in_way   parts the obstacle check found something in the way of, and
--            looked up what (checks.lua)
--   water    footprint tiles the obstacle check looked over for water, at
--            most once a check (water.lua)
--   stamps   copies stamped: the record, registrations and marks of each
--   built    parts stamped and Keep clear tiles cleared
--   ghosts   look-only ghosts pasted
--   poles    electric poles among the parts stamped or ghosts pasted: each
--            wires itself to every pole in reach
-- each at budget.COST's rate, so a spot pays for what it did however far
-- it got, a rule, the map or a probe ruling it out included.

local budget = require("scripts.core.budget")

local work = {}

local COST = budget.COST
local FIELDS = { "spots", "chunks", "probes", "checked", "in_way", "water", "stamps", "built", "ghosts", "poles" }

-- A record of nothing done yet, plus `fields` ({name = count}) if given.
function work.new(fields)
  local record = {}
  for _, name in ipairs(FIELDS) do record[name] = fields and fields[name] or 0 end
  return record
end

-- The record's estimate, in microseconds.
function work.cost(record)
  return record.spots * COST.spot + record.chunks * COST.chunk + record.probes * COST.probe
    + record.checked * COST.check_part + record.in_way * COST.part_in_way + (record.water or 0) * COST.water_tile
    + record.stamps * COST.stamp + (record.built + record.ghosts) * COST.stamp_part + (record.poles or 0) * COST.pole
end

-- Charges the record to the force; returns its estimate.
function work.charge(force_index, record)
  local cost = work.cost(record)
  budget.charge(force_index, cost)
  return cost
end

-- A design's parts: what a check looks at and a stamp builds, its entities
-- and its tiles (the measure of a step's work, pace.lua).
function work.parts(prepared)
  return (prepared.entity_count or 0) + (prepared.tile_count or 0)
end

-- A design's electric poles (none known for one prepared before they were
-- counted).
function work.poles(prepared)
  return prepared.pole_count or 0
end

-- What the obstacle check looks at, and a stamp builds or clears: the parts
-- and the Keep clear tiles.
function work.check_size(prepared)
  return work.parts(prepared) + (prepared.clears and #prepared.clears or 0)
end

return work
