-- The plan made visible: instance outlines coloured by state, a project's
-- open sockets as arrows (waiting ones with their reason), blocked sockets
-- as crosses with their reason, and, while a copy is built or waits for its
-- ore, where it grows next: a faint arrow on each socket it will open and a
-- dashed outline of the copy that socket would bring. Derived entirely from
-- the registry. A project's own marks are kept by marks.lua, which draws
-- only what changed and at most a fixed number of them, however long the
-- frontier; a copy's marks are redrawn when the copy changes. Complete and
-- retired instances draw nothing, so a finished field costs no render
-- objects, and neither does anything of a stopped project: it has left the
-- window, so its marks leave the map.

local const = require("scripts.const")
local frontier = require("scripts.core.frontier")
local draw = require("scripts.render.draw")
local marks = require("scripts.render.marks")

local overlay = {}

-- preview(project, socket): the footprint the next copy at a socket would
-- take, or nil (growth.preview, wired in control.lua: growth requires this
-- module through stamping, so it cannot be required here).
overlay.hooks = {}

local STATE = const.STATE
local PROJECT_STATE = const.PROJECT_STATE
local DASH, GAP = 0.45, 0.3   -- tiles: the next copy's outline is dashed, unlike a real one

local COLOR = draw.COLOR
local destroy_all, with = draw.destroy_all, draw.with

local function instance_label(instance)
  if instance.state == STATE.building then return { "seb-overlay.building", instance.ghosts_left or "?" } end
  if instance.state == STATE.stalled then
    return { "seb-overlay.stalled", instance.ghosts_left or "?", { "seb-reason." .. (instance.reason or const.REASON.no_progress) } }
  end
  if instance.state == STATE.incomplete then return { "seb-overlay.incomplete" } end
  return { "seb-overlay.retiring" }
end

-- A copy of a stopped (or forgotten) project keeps building, unmarked, like
-- any other ghost. A stamp made outside any project always draws.
local function unlisted(instance)
  local id = instance.project_id
  if not id then return false end
  local project = storage.projects[id]
  return not project or project.state == const.PROJECT_STATE.stopped
end

-- A finished copy waiting for its ore to run out shows where it looks.
local function draw_sensors(instance, base)
  local objects = {}
  for _, box in ipairs(instance.sensors or {}) do
    objects[#objects + 1] = rendering.draw_rectangle(with(base, {
      color = COLOR.ore, width = 2, filled = false, draw_on_ground = true,
      left_top = { box.left + 0.05, box.top + 0.05 }, right_bottom = { box.right - 0.05, box.bottom - 0.05 },
    }))
  end
  local box = instance.footprint
  objects[#objects + 1] = rendering.draw_text(with(base, {
    text = { "seb-overlay.waiting-ore" }, color = COLOR.ore, scale = 1.1, alignment = "center",
    target = { (box.left + box.right) / 2, box.top + 0.2 },
  }))
  return objects
end

local function dashed_box(objects, base, box, color)
  local l, t, r, b = box.left + 0.15, box.top + 0.15, box.right - 0.15, box.bottom - 0.15
  for _, edge in ipairs({ { l, t, r, t }, { r, t, r, b }, { r, b, l, b }, { l, b, l, t } }) do
    objects[#objects + 1] = rendering.draw_line(with(base, {
      color = color, width = 2, dash_length = DASH, gap_length = GAP, draw_on_ground = true,
      from = { edge[1], edge[2] }, to = { edge[3], edge[4] },
    }))
  end
end

-- Saves made before these marks existed have no table for them; it is made
-- here, where it is used, since such a save brings no configuration change.
local function next_store()
  local renders = storage.renders
  renders.next = renders.next or {}
  return renders.next
end

-- The project a copy still grows for: one that is growing or paused, and
-- that has counted the copy (marks drawn at stamp time would miss the
-- count and a fast fill's flag). A fast fill's copy opened its sockets when
-- placed; they draw as open sockets. A finished copy being updated in
-- place opened its sockets long ago: nothing comes next from it.
local function growing_project(instance)
  local project = instance.project_id and storage.projects[instance.project_id]
  if not project or project.dry_run or instance.opened_early or instance.updating == "complete" then return nil end
  if not project.instance_ids[instance.id] then return nil end
  if project.state ~= PROJECT_STATE.growing and project.state ~= PROJECT_STATE.paused then return nil end
  local pending = instance.state == STATE.building or instance.state == STATE.stalled
    or (instance.state == STATE.complete and instance.waiting_ore)
  return pending and project or nil
end

-- Only spots a rule does not already rule out show (preview gives nil for
-- those): an arrow with no copy to follow would promise growth that never
-- comes.
local function draw_next(base, project, instance)
  local objects, preview = {}, overlay.hooks.preview
  for _, socket in ipairs(frontier.sockets_of(project, instance)) do
    local box = preview and preview(project, socket)
    if box then
      draw.arrow(objects, base, socket, COLOR.next)
      dashed_box(objects, base, box, COLOR.next)
    end
  end
  return objects
end

-- Redrawn only when what it depends on changes: a copy's outline redraws on
-- every recount while robots build it, its next spots do not.
local function refresh_next(instance, base)
  local store = next_store()
  local project = base and growing_project(instance)
  local key = project and (instance.state .. ":" .. project.count .. ":" .. (instance.version or 0))
  local drawn = store[instance.id]
  if drawn and drawn.key == key then return end
  destroy_all(drawn and drawn.objects)
  store[instance.id] = key and { key = key, objects = draw_next(base, project, instance) } or nil
end

function overlay.refresh_instance(instance)
  local store = storage.renders.instances
  destroy_all(store[instance.id])
  store[instance.id] = nil
  local surface = game.surfaces[instance.surface_index]
  if not surface or unlisted(instance) then return refresh_next(instance, nil) end
  local base = draw.base(surface, instance.force_index)
  refresh_next(instance, base)
  if instance.state == STATE.complete and instance.waiting_ore then
    store[instance.id] = draw_sensors(instance, base)
    return
  end
  local color = COLOR[instance.state]
  if not color then return end
  local box = instance.footprint
  store[instance.id] = {
    rendering.draw_rectangle(with(base, {
      color = color, width = 2, filled = false, draw_on_ground = true,
      left_top = { box.left + 0.1, box.top + 0.1 }, right_bottom = { box.right - 0.1, box.bottom - 0.1 },
    })),
    rendering.draw_text(with(base, {
      text = instance_label(instance), color = color, scale = 1.1, alignment = "center",
      target = { (box.left + box.right) / 2, box.top + 0.2 },
    })),
  }
end

-- A project's own marks (marks.lua): the next sockets, the parked and
-- blocked ones, a plan's outlines (drawn once each, as they are planned).
overlay.refresh_project = marks.refresh
overlay.draw_planned = marks.draw_planned
overlay.drop_project = marks.drop

function overlay.drop_instance(instance_id)
  destroy_all(storage.renders.instances[instance_id])
  storage.renders.instances[instance_id] = nil
  local store = next_store()
  local drawn = store[instance_id]
  destroy_all(drawn and drawn.objects)
  store[instance_id] = nil
end

-- Redraws the copies of a project that show where they grow next: its count
-- reached its limit, so their next copies will never come.
function overlay.refresh_pending(project)
  local store = next_store()
  for id in pairs(project.instance_ids) do
    local instance = store[id] and storage.instances[id]
    if instance then overlay.refresh_instance(instance) end
  end
end

return overlay
