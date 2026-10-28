-- Keep clear tiles (DESIGN.md D41): tiles a design needs empty, marked with
-- the Keep clear marker, or with Negative Space's marker, which reads the
-- same (const.FOREIGN_MARKERS). They count in the copy's footprint
-- (prepare.lua), so other copies keep off them; here, before a stamp, a
-- building or ghost on one refuses the spot unless the stamp is superforced
-- and it is the force's own; after the stamp, trees and rocks on them (and,
-- superforced, the force's own buildings) are marked for removal, and so are
-- cliffs once the force may blow them up (cliffs.lua: the check looks for
-- cliffs on kept tiles first). Ore, items on the ground and things that move
-- are no obstacle. Each kept tile is looked at on its own (under.lua), never
-- the box around them all: two markers 400 tiles apart span 160,000 tiles.

local const = require("scripts.const")
local geometry = require("scripts.core.geometry")
local under = require("scripts.core.under")
local cliffs = require("scripts.core.cliffs")

local clearance = {}

local REASON = const.REASON

-- Never in the way of an empty tile.
local PASSING = {
  "resource", "item-entity", "character", "car", "spider-vehicle", "construction-robot", "logistic-robot",
  "combat-robot", "corpse", "character-corpse", "tile-ghost", "fish", "item-request-proxy", "explosion", "smoke",
  "particle-source", "projectile", "deconstructible-tile-proxy",
}
-- Cleared like the ground under any part: forced mode marks them too.
local NATURE = { tree = true, ["simple-entity"] = true }

-- What may stand in the way: anything but PASSING, NATURE and cliffs (the
-- engine filters by type, inverted).
local IN_THE_WAY = { "tree", "simple-entity", "cliff" }
for _, name in ipairs(PASSING) do IN_THE_WAY[#IN_THE_WAY + 1] = name end

-- What an entity in the way on a kept tile means for the stamp: nil (the
-- stamp will remove it), or the reason the spot is refused.
local function verdict(e, force, superforce)
  if e.name:find("^ltr%-cell%-") then return REASON.held_land end
  if superforce and e.force == force then return nil end
  return REASON.building
end

-- The kept tile an entity found in `box` (kept tiles, maybe a row of them)
-- covers, the leftmost and then topmost, as the map position of its centre.
local function tile_of(e, box)
  local b = e.bounding_box
  local x = math.max(box.left, math.floor(b.left_top.x + 0.01))
  local y = math.max(box.top, math.floor(b.left_top.y + 0.01))
  if x >= box.right or y >= box.bottom then x, y = box.left, box.top end
  return { x = x + 0.5, y = y + 0.5 }
end

-- nil when every kept tile can be cleared; else a reason and where.
function clearance.blocked(surface, force, plan)
  local kept = under.boxes(plan, "kept")
  local reason, where
  local filter = { type = IN_THE_WAY, invert = true, limit = not plan.superforce and 1 or nil }
  under.each(surface, nil, kept, filter, function(e, box)
    reason = verdict(e, force, plan.superforce)
    if not reason then return nil end
    where = tile_of(e, box)
    return under.STOP
  end)
  return reason, where
end

local function remove(e, force, superforce)
  if NATURE[e.type] then
    e.order_deconstruction(force)
  elseif e.type == "cliff" then
    if cliffs.explosive(force, e) then e.order_deconstruction(force) end
  elseif superforce and e.force == force then
    if e.type == "entity-ghost" then e.destroy() else e.order_deconstruction(force) end
  end
end

-- After the stamp: what stands on kept tiles is marked for removal, and so
-- is every cliff the check noted under the copy.
function clearance.clear(surface, force, plan)
  under.each(surface, nil, under.boxes(plan, "kept"), { type = PASSING, invert = true }, function(e)
    if e.valid and not e.to_be_deconstructed() then remove(e, force, plan.superforce) end
  end)
  cliffs.order(plan, force)
end

return clearance
