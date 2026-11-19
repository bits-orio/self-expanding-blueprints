-- What a drag of the area tool would do, shown while it is dragged (D63):
-- the outline of the first copy, at the corner the drag started at, and how
-- many copies the rectangle has room for. Green when a copy fits, red with
-- the size to drag when it does not.
--
-- The engine tells of a drag in flight through the preselection events
-- (Factorio 2.1.22): at most one a tick, only when the pointer moved, with
-- the raw rectangle and the corner it started at, which a right-click may
-- move mid-drag. They are best effort, so they only draw: releasing the
-- button (the selected-area events) stays the one thing that grows. One
-- outline and one line of text per player, moved in place; they are render
-- objects every peer holds, so they live in storage like any other. Never
-- e.tiles or e.entities: the rectangle alone says it all.

local geometry = require("scripts.core.geometry")
local placement = require("scripts.core.placement")
local registry = require("scripts.core.registry")
local tool = require("scripts.tool")

local fill_preview = {}

local FITS = { r = 0.30, g = 0.75, b = 0.35 }   -- the area tool's own green
local SHORT = { r = 0.95, g = 0.25, b = 0.20 }
local NORTH = geometry.NORTH

-- How many repeats of `step` fit in `room` beside the first copy.
local function more(room, step)
  return math.max(0, math.floor(room / step + 1e-6))
end

-- What a fill of `where` ({area = whole tiles, from_right, from_bottom})
-- begins with: {footprint, fits, columns, rows}, the first copy's place as
-- projects.start puts it and the grid of copies the rectangle has room for.
function fill_preview.plan(prepared, where)
  local seed = placement.seed(prepared, where, NORTH)
  if not seed then return nil end
  local box, area = placement.footprint(prepared, seed, NORTH), where.area
  local plan = { footprint = box, fits = geometry.contains_box(area, box), columns = 0, rows = 0 }
  if not plan.fits then return plan end
  local size = placement.repeat_size(prepared, NORTH)
  plan.columns = 1 + more(where.from_right and box.left - area.left or area.right - box.right, size.x)
  plan.rows = 1 + more(where.from_bottom and box.top - area.top or area.bottom - box.bottom, size.y)
  return plan
end

-- The line under the outline. A design with socket arrows grows through
-- them, so only its first copy is known; a plain one fills the grid, up to
-- the player's count.
local function caption(player, prepared, plan)
  if not plan.fits then
    local size = geometry.box_size(plan.footprint)
    return { "seb-overlay.fill-too-small", size.x, size.y }
  end
  if #prepared.sockets > 0 then return { "seb-overlay.fill-first" } end
  local count = registry.grow_count(registry.grow_options(player.index), true)
  local copies = plan.columns * plan.rows
  return { "seb-overlay.fill-copies", count and math.min(count, copies) or copies }
end

local function destroy(shown)
  if shown.box.valid then shown.box.destroy() end
  if shown.text.valid then shown.text.destroy() end
end

function fill_preview.clear(player)
  local state = storage.players[player.index]
  local shown = state and state.fill_preview
  if not shown then return end
  state.fill_preview = nil
  destroy(shown)
end

local function create(player, surface)
  local corner = { 0, 0 }
  return {
    surface_index = surface.index,
    box = rendering.draw_rectangle {
      color = FITS, width = 3, filled = false, surface = surface, players = { player },
      left_top = corner, right_bottom = corner,
    },
    text = rendering.draw_text {
      text = "", color = FITS, surface = surface, players = { player }, target = corner,
      scale = 1.5, scale_with_zoom = true, alignment = "center", vertical_alignment = "top",
    },
  }
end

-- The player's outline and text on `surface`: the ones drawn already, or
-- new ones when there are none or they are of another surface.
local function objects(player, surface)
  local state = registry.player(player.index)
  local shown = state.fill_preview
  if shown and shown.box.valid and shown.text.valid and shown.surface_index == surface.index then return shown end
  if shown then destroy(shown) end
  state.fill_preview = create(player, surface)
  return state.fill_preview
end

local function draw(player, surface, plan, text)
  local shown, box = objects(player, surface), plan.footprint
  local color = plan.fits and FITS or SHORT
  shown.box.set_corners({ box.left, box.top }, { box.right, box.bottom })
  shown.box.color = color
  shown.text.target = { (box.left + box.right) / 2, box.bottom + 0.2 }
  shown.text.text = text
  shown.text.color = color
end

-- The design the area tool grows, as it is: nothing is prepared for a look.
local function held_design(player)
  local lib = storage.libraries[player.force.index]
  local id = registry.player(player.index).tool_design
  local design = lib and id and lib.designs[id]
  if design and not design.stale and design.prepared and design.prepared.ok then return design end
end

local GROWS = {
  [defines.selection_mode.select] = true, [defines.selection_mode.alt_select] = true,
}

-- A drag began or moved. Only a drag that grows shows anything: the
-- right-drags act on copies, which are outlined while the tool is held.
function fill_preview.on_changed(event)
  local player = tool.player_of(event)
  if not player then return end
  local where = GROWS[event.selection_mode] and tool.where_of(event)
  local design = where and where.area and held_design(player)
  if not design then return fill_preview.clear(player) end
  where.area = geometry.tile_box(where.area)
  local plan = fill_preview.plan(design.prepared, where)
  if not plan then return fill_preview.clear(player) end
  draw(player, event.surface, plan, caption(player, design.prepared, plan))
end

-- The drag ended (released or called off), the tool left the hand, or the
-- player left or changed surface: nothing stays drawn. An event the engine
-- dropped is made up for by the next of these.
function fill_preview.on_ended(event)
  local player = game.get_player(event.player_index)
  if player then fill_preview.clear(player) end
end

return fill_preview
