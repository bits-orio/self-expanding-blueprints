-- A plan's look-only ghosts (D40): a dry run may paste its first copies as
-- ghosts, so the player sees the buildings themselves and not just
-- outlines. They belong to the neutral force, which no robots serve, so
-- nothing ever builds them. The paste is a forced one (each part that fits
-- goes down), and the removal orders it gives trees and rocks are taken
-- back at once, so nothing in the way is cleared. They go when the plan is
-- grown for real, stopped or forgotten, and give way to any copy stamped
-- or planned over them (previews.make_room). A copy whose parts stand over
-- anything of another team is not pasted: on a shared surface that team
-- could neither remove the neutral ghosts nor paste its own blueprints
-- through them.
--
-- Each pasted copy keeps its ghosts as a group with its footprint, filed by
-- the tile each stands on: project.previews = {{box, at = {[tile_key] =
-- {ghost, ...}}, count}, ...}, at most previews.MAX. A copy about to go
-- down tests its footprint against each group's box first, so a spot costs
-- a few box tests, and work in a group it overlaps only for the tiles it
-- covers (or the group's ghosts, if fewer).

local geometry = require("scripts.core.geometry")
local library = require("scripts.core.library")
local ghosts = require("scripts.core.ghosts")
local clearing = require("scripts.core.clearing")
local under = require("scripts.core.under")

local previews = {}

previews.MAX = 20   -- copies a plan may show as ghosts

-- Plans that hold preview ghosts now, so make_room costs nothing without.
local function live()
  storage.previews_live = storage.previews_live or {}
  return storage.previews_live
end

local function file(group, ghost)
  local p = ghost.position
  local key = geometry.tile_key(p.x, p.y)
  local list = group.at[key] or {}
  group.at[key] = list
  list[#list + 1] = ghost
  group.count = group.count + 1
end

-- The plan's groups. A save from before them holds one flat list of
-- ghosts, which becomes one group around them.
local function groups_of(project)
  local list = project.previews
  if not (list and list[1] and list[1].object_name) then return list or {} end
  local group = { at = {}, count = 0 }
  for _, ghost in pairs(list) do
    if ghost.valid then
      file(group, ghost)
      local x, y = math.floor(ghost.position.x), math.floor(ghost.position.y)
      group.box = geometry.union(group.box, geometry.box(x, y, x + 1, y + 1))
    end
  end
  project.previews = group.box and { group } or {}
  return project.previews
end

-- Whether anything of a force other than the plan's own (neutral and enemy
-- aside: trees, rocks, ore, biters) stands under the copy's parts.
local function others_in(surface, project, spot)
  local found = false
  local filter = { force = { project.force_index, "neutral", "enemy" }, invert = true, limit = 1 }
  under.each(surface, nil, under.join(under.boxes(spot, "entities"), under.boxes(spot, "tiles")), filter, function()
    found = true
    return under.STOP
  end)
  return found
end

-- Pastes a planned copy as ghosts while the plan has copies left to show.
-- Returns how many ghosts it made, for the advance's work budget.
function previews.paste(project, spot)
  if (project.preview_copies or 0) >= (project.preview_ghosts or 0) then return 0 end
  local surface = game.surfaces[project.surface_index]
  if not surface or others_in(surface, project, spot) then return 0 end
  local neutral = game.forces.neutral
  local unmarked = clearing.unmarked(surface, neutral, spot, false)
  local built = library.stamp_stack(spot.design).build_blueprint {
    surface = surface, force = neutral, position = spot.position, direction = spot.direction,
    build_mode = defines.build_mode.forced, raise_built = false,
  }
  clearing.take_back(unmarked, neutral)
  local group = { box = spot.footprint, at = {}, count = 0 }
  for _, ghost in pairs(built or {}) do
    if ghost.valid and ghosts.is_marker(ghost) then
      ghost.destroy()
    elseif ghost.valid then
      file(group, ghost)
    end
  end
  if group.count == 0 then return 0 end
  local groups = groups_of(project)
  groups[#groups + 1] = group
  project.previews = groups
  project.preview_copies = (project.preview_copies or 0) + 1
  live()[project.id] = true
  return group.count
end

local function destroy(list)
  for _, ghost in ipairs(list) do
    if ghost.valid then ghost.destroy() end
  end
end

function previews.clear(project)
  for _, group in ipairs(groups_of(project)) do
    for _, list in pairs(group.at) do destroy(list) end
  end
  project.previews = nil
  live()[project.id] = nil
end

local function take(group, key)
  local list = group.at[key]
  if not list then return end
  destroy(list)
  group.count = group.count - #list
  group.at[key] = nil
end

-- Removes the group's ghosts standing on tiles of `box`, tile by tile or
-- ghost by ghost, whichever is fewer. Returns the work done.
local function clear_inside(group, box)
  local l, t = math.floor(math.max(box.left, group.box.left)), math.floor(math.max(box.top, group.box.top))
  local r, b = math.ceil(math.min(box.right, group.box.right)), math.ceil(math.min(box.bottom, group.box.bottom))
  if (r - l) * (b - t) <= group.count then
    for x = l, r - 1 do
      for y = t, b - 1 do take(group, geometry.tile_key(x, y)) end
    end
    return (r - l) * (b - t)
  end
  local looked = group.count
  for key in pairs(group.at) do
    local x, y = geometry.tile_xy(key)
    if x >= l and x < r and y >= t and y < b then take(group, key) end
  end
  return looked
end

-- The plan's groups the footprint overlaps give way; emptied ones go.
local function clear_plan(project, footprint)
  local kept, work = {}, 0
  for _, group in ipairs(groups_of(project)) do
    if geometry.overlaps(group.box, footprint) then work = work + clear_inside(group, footprint) end
    if group.count > 0 then kept[#kept + 1] = group end
  end
  project.previews = kept
  if #kept == 0 then live()[project.id] = nil end
  return work
end

-- Preview ghosts are only pictures: a copy about to be stamped or planned
-- over them (by anyone but their own plan) takes their place. Returns the
-- work done (box tests, and tiles or ghosts looked at).
function previews.make_room(surface_index, footprint, except_id)
  local plans, work = live(), 0
  for id in pairs(plans) do
    local project = storage.projects[id]
    if not project then plans[id] = nil end
    if id ~= except_id and project and project.surface_index == surface_index then
      work = work + #groups_of(project) + clear_plan(project, footprint)
    end
  end
  return work
end

return previews
