-- The shifts an update in place tries (update_match.lua): each pair of a
-- copy's entity and a part of the new version of the same name proposes the
-- shift that lays the part on the entity (world = shift + turned blueprint
-- position). A copy with few pairs counts them all; one with more votes with
-- its entities of the rarest names only, and its leading shifts are tried,
-- with the four that lay the parts flush with the copy's sides (a blueprint
-- edited by adding or taking rows keeps one side of each pair where it was,
-- which a vote among many identical parts cannot tell).

local geometry = require("scripts.core.geometry")
local places = require("scripts.core.update_places")

local update_vote = {}

-- Counting every pair is as many steps as there are entities times parts:
-- thousands of lamps are millions, in one tick. Above this many pairs a
-- copy votes with about this many.
update_vote.PAIRS = 2500
local LEADERS = 8

local distance2 = places.distance2

-- Each entity of `voters` and each part of its name propose a shift, keyed
-- by its place from the first one proposed (every shift that lays a part
-- on an entity is near it).
local function tally(voters, by_name)
  local votes, shifts, first = {}, {}, nil
  for _, s in ipairs(voters) do
    for _, p in ipairs(by_name[s.name] or {}) do
      local shift = { x = s.x - p.x, y = s.y - p.y }
      first = first or shift
      local key = places.key(shift.x, shift.y, first)
      if key then votes[key], shifts[key] = (votes[key] or 0) + 1, shift end
    end
  end
  return votes, shifts
end

-- Every pair counted: the shift with the most votes, among equal votes the
-- one nearest `home`; nil when no pair exists.
function update_vote.exact(entities, by_name, home)
  local votes, shifts = tally(entities, by_name)
  local best, most
  for key, n in pairs(votes) do
    if not best or n > most or (n == most and distance2(shifts[key], home) < distance2(shifts[best], home)) then
      best, most = key, n
    end
  end
  return best and shifts[best]
end

-- The copy's entities grouped by how many parts share their name, and
-- those counts, rarest first.
local function by_rarity(entities, by_name)
  local groups, counts = {}, {}
  for _, s in ipairs(entities) do
    local parts = by_name[s.name]
    if parts then
      local n = #parts
      if not groups[n] then groups[n], counts[#counts + 1] = {}, n end
      local group = groups[n]
      group[#group + 1] = s
    end
  end
  table.sort(counts)
  return groups, counts
end

local function by_unit(a, b)
  return a.unit < b.unit
end

-- The entities of the rarest names, as many as about PAIRS pairs allow (at
-- least one): whole groups from the rarest up, then the group that would
-- pass the budget in unit order, while they fit.
local function voters_of(entities, by_name)
  local groups, counts = by_rarity(entities, by_name)
  local voters, left = {}, update_vote.PAIRS
  for _, n in ipairs(counts) do
    local group = groups[n]
    if #group * n > left then table.sort(group, by_unit) end
    for _, s in ipairs(group) do
      if #voters > 0 and n > left then return voters end
      voters[#voters + 1] = s
      left = left - n
    end
  end
  return voters
end

-- Whether shift key a leads b: more votes, then nearer home, then the key.
local function leads(a, b, votes, distance)
  if votes[a] ~= votes[b] then return votes[a] > votes[b] end
  if distance[a] ~= distance[b] then return distance[a] < distance[b] end
  return a < b
end

-- The LEADERS leading shifts of a vote, best first, picked in one pass.
local function leaders_of(votes, shifts, home)
  local distance, top = {}, {}
  for key, shift in pairs(shifts) do
    distance[key] = distance2(shift, home)
    local i = #top + 1
    while i > 1 and leads(key, top[i - 1], votes, distance) do i = i - 1 end
    if i <= LEADERS then
      table.insert(top, i, key)
      top[LEADERS + 1] = nil
    end
  end
  local list = {}
  for i, key in ipairs(top) do list[i] = shifts[key] end
  return list
end

-- The box holding the copy's entities, and the one holding the parts.
local function extents(entities, by_name)
  local e, p
  for _, s in ipairs(entities) do e = geometry.union(e, geometry.box(s.x, s.y, s.x, s.y)) end
  for _, list in pairs(by_name) do
    for _, q in ipairs(list) do p = geometry.union(p, geometry.box(q.x, q.y, q.x, q.y)) end
  end
  return e, p
end

-- The parts flush with the copy's entities on two of its sides: left or
-- right, top or bottom.
local function edge_shifts(entities, by_name)
  local e, p = extents(entities, by_name)
  if not (e and p) then return {} end
  local list = {}
  for _, x in ipairs({ e.left - p.left, e.right - p.right }) do
    for _, y in ipairs({ e.top - p.top, e.bottom - p.bottom }) do list[#list + 1] = { x = x, y = y } end
  end
  return list
end

-- The shifts worth trying for a copy with too many pairs to count.
function update_vote.candidates(entities, by_name, home)
  local votes, shifts = tally(voters_of(entities, by_name), by_name)
  local list = leaders_of(votes, shifts, home)
  for _, shift in ipairs(edge_shifts(entities, by_name)) do list[#list + 1] = shift end
  return list
end

return update_vote
