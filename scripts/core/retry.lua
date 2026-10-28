-- Blocked sockets tried again. A socket closed by something on the map that
-- can change (a building, tree or rock, a cliff, water, a probe that did not
-- hold, enemies, land not charted yet) keeps its socket with its mark
-- (project.blocked, the newest const.MAX_BLOCKED_KEPT). It goes back to the
-- frontier
--   by hand    the Retry button on the project's row, or a Shift +
--              right-drag of the area tool over the marks (tool.lua)
--   by itself  when what stood at its mark leaves the map: mined,
--              destroyed, built over with a tile, its ore run out, its
--              chunk charted
-- A finished project grows on from there; a stopped one, or one at its
-- count, never does.
-- Marks are indexed by chunk (storage.blocked_chunks[surface][chunk key] =
-- {[project_id] = true}), so a removed entity looks only at the projects with
-- a mark in its chunk; an index entry no mark answers any more is dropped
-- when it is looked at.

local const = require("scripts.const")
local geometry = require("scripts.core.geometry")
local registry = require("scripts.core.registry")
local frontier = require("scripts.core.frontier")
local history = require("scripts.core.history")
local holds = require("scripts.core.holds")
local overlay = require("scripts.render.overlay")

local retry = {}

-- changed(project): set by projects.lua so open windows refresh.
retry.hooks = {}

local REASON = const.REASON
local STATE = const.PROJECT_STATE

-- What the map can stop being. A design that is gone or broken, a spot off
-- its grid and a copy over its own parent stay closed.
local RETRYABLE = {
  [REASON.water] = true, [REASON.cliff] = true, [REASON.building] = true, [REASON.uncharted] = true,
  [REASON.stamp_short] = true, [REASON.no_resource] = true, [REASON.probe] = true,
  [REASON.held_land] = true, [REASON.enemies] = true,
}

-- An event's sockets wait this long, so the rest of a clearing (a robot
-- swarm taking trees one by one) is gone too when they are tried.
local SETTLE_TICKS = 60

local CHUNK = 32

local function chunk_of(position)
  return geometry.chunk_key(math.floor(position.x / CHUNK), math.floor(position.y / CHUNK))
end

local function chunks_on(surface_index)
  storage.blocked_chunks = storage.blocked_chunks or {}
  local on = storage.blocked_chunks[surface_index] or {}
  storage.blocked_chunks[surface_index] = on
  return on
end

-- A blocked mark just recorded (loop.lua): its socket is kept when the map
-- can change under it.
function retry.keep(project, socket, entry)
  if not RETRYABLE[entry.reason] then return end
  entry.socket = socket
  local on = chunks_on(project.surface_index)
  local key = chunk_of(entry.position)
  local ids = on[key] or {}
  on[key] = ids
  ids[project.id] = true
end

-- A stopped project, or one at its count, grows nothing more.
local function done(project)
  local max = project.rules.max_instances
  return project.state == STATE.stopped or (max ~= nil and project.count >= max)
end

function retry.count(project)
  if done(project) then return 0 end
  local n = 0
  for _, entry in ipairs(project.blocked) do
    if entry.socket then n = n + 1 end
  end
  return n
end

-- The marks of the project that pass `pick` leave project.blocked, and
-- their sockets go to the back of the frontier. Returns how many.
local function reopen(project, pick, delay, player)
  if done(project) then return 0 end
  local kept, sockets = {}, {}
  for _, entry in ipairs(project.blocked) do
    if entry.socket and pick(entry) then
      sockets[#sockets + 1] = entry.socket
      local closed = project.closed[entry.reason]
      if closed then project.closed[entry.reason] = closed > 1 and closed - 1 or nil end
    else
      kept[#kept + 1] = entry
    end
  end
  if #sockets == 0 then return 0 end
  project.blocked = kept
  frontier.reopen(project, sockets)
  if project.state == STATE.finished then project.state = STATE.growing end
  project.nothing_built, project.parked_key = nil, nil
  history.add(project, { kind = "retried", count = #sockets, player_index = player and player.index })
  holds.queue_advance(project, delay)
  overlay.refresh_project(project)
  if retry.hooks.changed then retry.hooks.changed(project) end
  return #sockets
end

local function any()
  return true
end

-- Every blocked socket of the project, now (the row's Retry button).
function retry.project(project, player)
  return reopen(project, any, 1, player)
end

-- The force's blocked sockets whose marks lie in `box` on the surface (a
-- drag of the area tool). Returns how many.
function retry.area(force_index, surface_index, box, player)
  local function inside(entry) return geometry.contains_point(box, entry.position) end
  local n = 0
  for id in pairs(registry.project_ids(force_index)) do
    local project = storage.projects[id]
    if project and project.surface_index == surface_index then n = n + reopen(project, inside, 1, player) end
  end
  return n
end

local function marks_in(project, key)
  for _, entry in ipairs(project.blocked) do
    if entry.socket and chunk_of(entry.position) == key then return true end
  end
  return false
end

-- Something left the map in `box`: the marks there of any project are tried
-- again soon.
local function freed(surface_index, box)
  local on = storage.blocked_chunks and storage.blocked_chunks[surface_index]
  if not on then return end
  local function inside(entry) return geometry.contains_point(box, entry.position) end
  geometry.each_chunk(box, function(cx, cy)
    local key = geometry.chunk_key(cx, cy)
    local ids = on[key]
    if not ids then return end
    for id in pairs(ids) do
      local project = storage.projects[id]
      if project then reopen(project, inside, SETTLE_TICKS) end
      if not (project and marks_in(project, key)) then ids[id] = nil end
    end
    if next(ids) == nil then on[key] = nil end
  end)
end

-- A mark is where the first obstacle's centre, the first wet tile or the
-- probe's tile was: an entity's own box, a little wider, holds it.
local function entity_box(entity)
  local area = geometry.from_area(entity.bounding_box)
  return geometry.box(area.left - 0.5, area.top - 0.5, area.right + 0.5, area.bottom + 0.5)
end

function retry.on_entity_removed(event)
  local entity = event.entity
  if entity and entity.valid then freed(entity.surface.index, entity_box(entity)) end
end

function retry.on_tiles_built(event)
  local box
  for _, tile in ipairs(event.tiles) do
    local p = tile.position
    box = geometry.union(box, geometry.box(p.x, p.y, p.x + 1, p.y + 1))
  end
  if box then freed(event.surface_index, box) end
end

function retry.on_chunk_charted(event)
  local p = event.position
  freed(event.surface_index, geometry.box(p.x * CHUNK, p.y * CHUNK, (p.x + 1) * CHUNK, (p.y + 1) * CHUNK))
end

function retry.drop_surface(surface_index)
  if storage.blocked_chunks then storage.blocked_chunks[surface_index] = nil end
end

return retry
