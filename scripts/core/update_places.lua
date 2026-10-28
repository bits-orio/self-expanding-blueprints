-- Places near a copy as whole numbers, for an update in place
-- (update_match.lua, update_vote.lua): the copy of a large design compares
-- tens of thousands of places in one tick, and numbers cost far less than
-- string keys.

local update_places = {}

-- 1/256 tile steps (as geometry.position_key rounds) up to 4096 tiles from
-- the base either way, far more than a design reaches
-- (const.MAX_DESIGN_SPAN), with room for a facing; exact in a double.
local STEPS, HALF, ROW = 256, 2 ^ 20, 2 ^ 21

-- The place (x, y) near `base` as one number; nil farther away, where
-- nothing matches it.
function update_places.key(x, y, base)
  local i = math.floor((x - base.x) * STEPS + 0.5)
  local j = math.floor((y - base.y) * STEPS + 0.5)
  if i < -HALF or i >= HALF or j < -HALF or j >= HALF then return nil end
  return (i + HALF) * ROW + (j + HALF)
end

-- The table under `name` in `sets`, made on first use.
function update_places.set_of(sets, name)
  local set = sets[name]
  if not set then
    set = {}
    sets[name] = set
  end
  return set
end

function update_places.distance2(a, b)
  return (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2
end

return update_places
