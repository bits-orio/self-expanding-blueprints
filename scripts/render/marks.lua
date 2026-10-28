-- A project's marks on the map: an arrow on each of the next sockets it
-- tries, in its order (at most const.MAX_DRAWN_SOCKETS; the one a gate
-- holds says why), the sockets no robots reach and those waiting for the
-- copy they grow from to be removed (as many at most each) and the
-- blocked ones it remembers (const.MAX_BLOCKED_KEPT), each with its
-- reason, and a plan's planned copies as outlines. A refresh keeps every
-- mark that still stands and draws only the new ones, so an advance costs
-- about the sockets it moved, however many are open; a planned copy's
-- outline is drawn once, when it is planned. All of it goes when the
-- project stops, is forgotten or grown for real (marks.drop).

local const = require("scripts.const")
local frontier = require("scripts.core.frontier")
local draw = require("scripts.render.draw")

local marks = {}

local COLOR = draw.COLOR
local MAX = const.MAX_DRAWN_SOCKETS

-- Nothing of a stopped project is drawn: it has left the window.
local function base_of(project)
  local surface = game.surfaces[project.surface_index]
  if not surface or project.state == const.PROJECT_STATE.stopped then return nil end
  return draw.base(surface, project.force_index)
end

local function outline(base, copy)
  local box = copy.footprint
  return rendering.draw_rectangle(draw.with(base, {
    color = COLOR.planned, width = 2, filled = false, draw_on_ground = true,
    left_top = { box.left + 0.15, box.top + 0.15 }, right_bottom = { box.right - 0.15, box.bottom - 0.15 },
  }))
end

-- The project's marks: {sockets = {[socket] = mark}, parked = {[socket] =
-- mark}, awaiting = {[socket] = mark}, blocked = {[entry] = mark}, planned
-- = {outline, ...}}, a mark being {key = what it shows, objects}. A save
-- from before holds one list of every object: it goes, and a plan's
-- outlines are drawn again; a store from before awaiting sockets gets
-- their set. Returns the store and whether it was made now (every outline
-- drawn).
local function store_of(project, base)
  local all = storage.renders.projects
  local store = all[project.id]
  if store and store.sockets then
    store.awaiting = store.awaiting or {}
    return store, false
  end
  draw.destroy_all(store)
  store = { sockets = {}, parked = {}, awaiting = {}, blocked = {}, planned = {} }
  for _, copy in pairs(project.planned or {}) do store.planned[#store.planned + 1] = outline(base, copy) end
  all[project.id] = store
  return store, true
end

-- An open socket's arrow, or a waiting one with why (`key` is a reason).
local function socket_mark(base, socket, key)
  local objects = {}
  draw.arrow(objects, base, socket, key == "open" and COLOR.open or COLOR.waiting)
  if key == "open" then return objects end
  objects[2] = rendering.draw_text(draw.with(base, {
    text = { "seb-reason." .. key }, color = COLOR.waiting, scale = 0.9,
    alignment = "center", target = { socket.position.x, socket.position.y + 0.5 },
  }))
  return objects
end

local function cross(base, entry)
  return {
    rendering.draw_sprite(draw.with(base, {
      sprite = "seb-overlay-blocked", tint = COLOR.blocked, x_scale = 0.5, y_scale = 0.5, target = entry.position,
    })),
    rendering.draw_text(draw.with(base, {
      text = { "seb-reason." .. entry.reason }, color = COLOR.blocked, scale = 0.9,
      alignment = "center", target = { entry.position.x, entry.position.y + 0.45 },
    })),
  }
end

-- Brings `set` (item -> mark) in line with `items`: an item keeps the mark
-- it has while it is drawn as key_of(item) says, else is drawn again with
-- paint(item, key); the marks of items no longer listed go. `pass` tells
-- this refresh's marks from older ones.
local function sync(set, items, key_of, paint, pass)
  for _, item in ipairs(items) do
    local key, mark = key_of(item), set[item]
    if not (mark and mark.key == key and mark.objects[1].valid) then
      if mark then draw.destroy_all(mark.objects) end
      mark = { key = key, objects = paint(item, key) }
      set[item] = mark
    end
    mark.pass = pass
  end
  for item, mark in pairs(set) do
    if mark.pass ~= pass then
      draw.destroy_all(mark.objects)
      set[item] = nil
    end
  end
end

local function first(list, n)
  if #list <= n then return list end
  local out = {}
  for i = 1, n do out[i] = list[i] end
  return out
end

function marks.refresh(project)
  local base = base_of(project)
  if not base then return marks.drop(project.id) end
  local store = store_of(project, base)
  local pass = (store.pass or 0) + 1
  store.pass = pass
  local ahead = frontier.ahead(project, MAX)
  -- A gate holds the socket the project tries next; that one shows why.
  local held = project.gate and ahead[1]
  local function paint(socket, key) return socket_mark(base, socket, key) end
  sync(store.sockets, ahead, function(socket) return socket == held and project.gate.reason or "open" end, paint, pass)
  sync(store.parked, first(project.parked, MAX), function() return const.REASON.no_network end, paint, pass)
  sync(store.awaiting, first(project.awaiting or {}, MAX), function() return const.REASON.parent_retiring end,
    paint, pass)
  sync(store.blocked, project.blocked, function() return "blocked" end,
    function(entry) return cross(base, entry) end, pass)
end

-- Drawn once, when the copy is planned (loop.lua).
function marks.draw_planned(project, copy)
  local base = base_of(project)
  if not base then return end
  local store, made = store_of(project, base)
  if not made then store.planned[#store.planned + 1] = outline(base, copy) end
end

function marks.drop(project_id)
  local all = storage.renders.projects
  local store = all[project_id]
  all[project_id] = nil
  if not (store and store.sockets) then return draw.destroy_all(store) end
  for _, set in ipairs({ store.sockets, store.parked, store.awaiting or {}, store.blocked }) do
    for _, mark in pairs(set) do draw.destroy_all(mark.objects) end
  end
  draw.destroy_all(store.planned)
end

return marks
