-- An update in place (update.lua) matched against the copy it updates:
-- where the new version lies over it, and what of it already stands.
--   The copy's built entities are read from the engine once (standing).
--   Blueprint coordinates move when a blueprint is edited, so the new
--   version goes where most of its parts coincide with those entities, of
--   the shifts update_vote.lua proposes; among equal ones the shift nearest
--   the copy's own blueprint origin wins (a blueprint edited in place keeps
--   its coordinates, so the true shift is usually that origin; copies from
--   before 0.2 fall back to their build position).
--   A part matching a standing entity by name, place and facing stays (the
--   paste keeps it); the others are fresh, and the entities no part matches
--   are dropped.

local geometry = require("scripts.core.geometry")
local places = require("scripts.core.update_places")
local update_vote = require("scripts.core.update_vote")

local update_match = {}

local place_key, set_of, distance2 = places.key, places.set_of, places.distance2

-- The new version's parts turned by `direction`: {by_name = their
-- positions by name, present = by name the set of their places from the
-- first part (blueprint coordinates can be far from the blueprint's
-- origin), to ask whether a part is there, first = that part's position}.
local function turned_parts(prepared, direction)
  local by_name, present, first = {}, {}, nil
  for _, e in ipairs(prepared.placements) do
    local p = geometry.rotate(e.position, direction)
    first = first or p
    local list = set_of(by_name, e.name)
    list[#list + 1] = p
    local key = place_key(p.x, p.y, first)
    if key then set_of(present, e.name)[key] = true end
  end
  return { by_name = by_name, present = present, first = first }
end

-- How many of the copy's entities have a part of their name where the new
-- version would put it, at `shift`; it stops counting once the entities
-- left could no longer make more than `most`.
local function support(entities, parts, shift, most)
  local n, left = 0, #entities
  local base = { x = shift.x + parts.first.x, y = shift.y + parts.first.y }
  for _, s in ipairs(entities) do
    local set = parts.present[s.name]
    local key = set and place_key(s.x, s.y, base)
    if key and set[key] then n = n + 1 end
    left = left - 1
    if most and n + left <= most then return n end
  end
  return n
end

-- How many (entity, part of its name) pairs there are, and how many of the
-- copy's entities any one shift could lay a part on at most.
local function counts(entities, by_name)
  local pair_count, per_name, possible = 0, {}, 0
  for _, s in ipairs(entities) do
    local list = by_name[s.name]
    if list then
      pair_count = pair_count + #list
      per_name[s.name] = (per_name[s.name] or 0) + 1
    end
  end
  for name, n in pairs(per_name) do possible = possible + math.min(n, #by_name[name]) end
  return pair_count, possible
end

-- Of the candidate shifts, the one most entities coincide under: home
-- (`at_home` of them) first, then the others nearest home first, so the
-- nearest of equals wins and a candidate stops counting once it cannot win.
local function best_of(entities, parts, home, at_home, candidates)
  table.sort(candidates, function(a, b)
    local da, db = distance2(a, home), distance2(b, home)
    if da ~= db then return da < db end
    if a.x ~= b.x then return a.x < b.x end
    return a.y < b.y
  end)
  local best, most = home, at_home
  for _, shift in ipairs(candidates) do
    local n = support(entities, parts, shift, most)
    if n > most then best, most = shift, n end
  end
  return { x = best.x, y = best.y }
end

-- The shift under which most of the copy's entities coincide with the new
-- version's parts, or nil when none does. `entities` are the copy's built
-- entities as read once (update_match.standing). The copy's own shift is
-- taken at once when as many coincide there as any shift could make.
function update_match.shift(instance, prepared, entities)
  local parts = turned_parts(prepared, instance.direction)
  local by_name = parts.by_name
  local pair_count, possible = counts(entities, by_name)
  local home = instance.origin or instance.position
  if pair_count <= update_vote.PAIRS then return update_vote.exact(entities, by_name, home) end
  local at_home = support(entities, parts, home)
  if at_home == possible then return { x = home.x, y = home.y } end
  return best_of(entities, parts, home, at_home, update_vote.candidates(entities, by_name, home))
end

-- The copy's built entities as plain data: {entity, unit, name, x, y,
-- direction} each.
function update_match.standing(instance)
  local list = {}
  for unit, entity in pairs(instance.entities) do
    if entity.valid then
      local p = entity.position
      list[#list + 1] = { entity = entity, unit = unit, name = entity.name, x = p.x, y = p.y, direction = entity.direction }
    end
  end
  return list
end

-- Whether a prototype can face another way than north, by name: constant
-- for the session (prototypes cannot change while the script runs; rebuilt
-- on every load).
local turns = {}

-- A built entity's facing, as the blueprint would give it: entities that
-- cannot turn always face north.
local function facing(name, direction)
  local can = turns[name]
  if can == nil then
    local proto = prototypes.entity[name]
    can = not proto or proto.supports_direction
    turns[name] = can
  end
  return can and (direction or 0) or 0
end

-- A part's place and facing near `base`, as one number; nil far away.
local function part_key(name, x, y, direction, base)
  local key = place_key(x, y, base)
  return key and key * 16 + facing(name, direction)
end

local function holds(sets, name, key)
  local set = key and sets[name]
  return set ~= nil and set[key] == true
end

-- The new version laid by `plan` against the copy's standing entities:
-- its parts not standing yet, and the entities no part of it matches.
function update_match.diff(entities, plan)
  local base, have = plan.position, {}
  for _, s in ipairs(entities) do
    s.key = part_key(s.name, s.x, s.y, s.direction, base)
    if s.key then set_of(have, s.name)[s.key] = true end
  end
  local prepared, direction, keep, fresh = plan.prepared, plan.direction, {}, {}
  -- placement.world, without a table per part.
  local o = prepared.offsets[direction]
  local ox, oy = base.x + o.x, base.y + o.y
  for _, e in ipairs(prepared.placements) do
    local rx, ry = geometry.rotate_xy(e.position.x, e.position.y, direction)
    local key = part_key(e.name, ox + rx, oy + ry, geometry.turn(e.direction, direction), base)
    if key then set_of(keep, e.name)[key] = true end
    if not holds(have, e.name, key) then fresh[#fresh + 1] = e end
  end
  local dropped = {}
  for _, s in ipairs(entities) do
    if not holds(keep, s.name, s.key) then dropped[#dropped + 1] = s end
  end
  return fresh, dropped
end

return update_match
