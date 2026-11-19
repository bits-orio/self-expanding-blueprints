-- fill_preview.lua: what the area tool shows while it is dragged.
-- No script can drag the mouse, so the handler is called through the mod's
-- test seam (scripts/remote/test_seam.lua) with events as the engine sends
-- them; the real drag is on dev/PLAYTEST.md.
--   plan:  the preview puts the first copy where a real fill puts it and
--          counts the copies a real fill plans, from either corner
--   drag:  green with the count, red with the size to drag when no copy
--          fits; drawn once and moved; drawn for the dragging player alone;
--          nothing for a right-drag; gone when the drag ends

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "fill_preview" }

local SEAM = rig.REMOTE .. "-test"
local REGION = 204
local CELL = { rig.panel(1.5, 1.5), rig.panel(4.5, 1.5) }   -- 6 x 3
local AREA = { 0, 0, 20, 10 }                               -- room for 3 x 3

local function seam(fn, ...)
  return remote.call(SEAM, fn, ...)
end

local function force_index()
  return game.forces[rig.FORCE].index
end

function case.setup(surface)
  rig.floor(surface, rig.box(rig.region(REGION), -10, -10, 40, 30))
  storage.fill_preview = { cell = rig.design(CELL, "Preview fill") }
end

function case.start(surface)
  local o = rig.region(REGION)
  local id, reason = rig.call("start_project", {
    force = rig.FORCE, surface = surface, design = storage.fill_preview.cell, charted_only = false, dry_run = true,
    area = rig.box(o, AREA[1], AREA[2], AREA[3], AREA[4]),
  })
  check.truthy("fill_preview the real fill starts", id, reason)
  storage.fill_preview.project = id
end

local function plan(where)
  return seam("fill_plan", force_index(), storage.fill_preview.cell, where)
end

-- A preselection event as the engine sends it: the raw rectangle, the
-- cursor at its bottom right.
local function drag(surface, box, mode)
  return seam("drag", {
    player_index = 1, surface = surface, selection_mode = mode or defines.selection_mode.select,
    area = { left_top = { x = box.left, y = box.top }, right_bottom = { x = box.right, y = box.bottom } },
    cursor_position = { x = box.right, y = box.bottom },
  }, storage.fill_preview.cell)
end

local function dragged(surface)
  if not game.get_player(1) then return check.info("fill_preview drag: no player on this engine, handler not run") end
  local o = rig.region(REGION)
  local shown = drag(surface, rig.box(o, 0.3, 0.4, 19.6, 9.7))
  check.same("fill_preview the drag outlines the first copy", shown and { shown.left, shown.top, shown.right, shown.bottom },
    { o.x, o.y, o.x + 6, o.y + 3 })
  -- A text's parameters read back as strings.
  check.same("fill_preview in green, with the count", shown and { shown.green, shown.text[1], shown.text[2] },
    { true, "seb-overlay.fill-copies", "9" })
  local moved = drag(surface, rig.box(o, 0.3, 0.4, 4.2, 2.1))
  check.same("fill_preview a drag too small is red and says the size", moved and { moved.green, moved.text[1], moved.text[2], moved.text[3] },
    { false, "seb-overlay.fill-too-small", "6", "3" })
  check.eq("fill_preview the outline is moved, not drawn again", moved and moved.box_id, shown and shown.box_id)
  -- Render objects without a players list are drawn for everyone.
  check.same("fill_preview only the dragging player sees the outline and the text",
    moved and { moved.box_players, moved.text_players }, { { 1 }, { 1 } })
  check.eq("fill_preview a right-drag shows nothing", drag(surface, rig.box(o, 0, 0, 20, 10), defines.selection_mode.reverse_select), nil)
  check.truthy("fill_preview a drag shows again", drag(surface, rig.box(o, 0, 0, 20, 10)))
  check.eq("fill_preview the end of the drag clears it", seam("end_drag", 1), nil)
end

local function verify(surface)
  local o = rig.region(REGION)
  local where = { area = rig.box(o, AREA[1], AREA[2], AREA[3], AREA[4]) }
  local p = rig.call("get_project", storage.fill_preview.project)
  local first = plan(where)
  check.same("fill_preview the preview's grid", first and { first.fits, first.columns, first.rows }, { true, 3, 3 })
  check.eq("fill_preview a real fill plans as many copies", p and p.count, first and first.columns * first.rows)
  where.from_right, where.from_bottom = true, true
  local back = plan(where)
  check.same("fill_preview from the far corner the first copy sits in it", back and { back.footprint.right, back.footprint.bottom, back.columns, back.rows },
    { o.x + 20, o.y + 10, 3, 3 })
  dragged(surface)
end

case.checks = { [1500] = verify }

return case
