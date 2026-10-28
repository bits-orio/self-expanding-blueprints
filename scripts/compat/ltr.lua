-- Land Title Registry (DESIGN.md section 6): copies grow only on land the
-- team holds well enough. The engine enforces that by itself (the
-- registry's blocker entities collide with whatever a cell does not
-- permit), so the per-part placement check already refuses a stamp before
-- anything is built; this only names why, "outside held land", instead of
-- "a building is in the way".

local ltr = {}

local BLOCKERS = { "ltr-cell-wilderness", "ltr-cell-trail", "ltr-cell-rampart" }

-- The blocker names this game knows (none without the registry).
local known
local function blockers()
  if known then return known end
  known = {}
  for _, name in ipairs(BLOCKERS) do
    if prototypes.entity[name] then known[#known + 1] = name end
  end
  return known
end

-- Whether one of the registry's blockers stands in `area`.
function ltr.blocks(surface, area)
  local names = blockers()
  if #names == 0 then return false end
  return surface.count_entities_filtered { area = area, name = names, limit = 1 } > 0
end

return ltr
