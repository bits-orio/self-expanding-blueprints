-- Pictures of designs: a camera onto the design's built copy in the gallery
-- (core/gallery.lua). Hovering a design in the list shows a card beside the
-- window with the picture and what the design is made of; the grow section
-- shows the chosen design's picture. A card never takes clicks, so it cannot
-- get between the pointer and the window.

local library = require("scripts.core.library")
local gallery = require("scripts.core.gallery")
local design_text = require("scripts.gui.design_text")

local preview = {}

local CARD = "seb-preview"
local CARD_SIZE = { width = 300, height = 220 }
local WINDOW_WIDTH = 548     -- the main window's outer width at scale 1
local GAP = 8
local TILE_PIXELS = 32       -- a tile on screen at zoom 1
local MAX_ZOOM = 1

-- The picture of a design, made now if it was never made (a save from before
-- the gallery existed).
local function view_of(design)
  local view = gallery.view(design)
  if view then return view end
  gallery.build(design, library.stamp_stack(design))
  return gallery.view(design)
end

-- A camera framing a design's picture inside `size` (GUI pixels), or a
-- label when there is none.
function preview.camera(parent, player, design, size)
  local view = view_of(design)
  if not view then
    local none = parent.add { type = "label", caption = { "seb-gui.no-picture" } }
    none.style.width = size.width
    return none
  end
  local box = view.footprint
  local w, h = box.right - box.left + 2, box.bottom - box.top + 2
  local zoom = math.min(MAX_ZOOM, size.width / (w * TILE_PIXELS), size.height / (h * TILE_PIXELS))
  local frame = parent.add { type = "frame", style = "deep_frame_in_shallow_frame" }
  local camera = frame.add {
    type = "camera", position = { (box.left + box.right) / 2, (box.top + box.bottom) / 2 },
    surface_index = view.surface.index, zoom = zoom * player.display_scale,
  }
  -- Shaped like the design, so no neighbouring picture shows at its sides.
  camera.style.width = math.min(size.width, math.ceil(w * TILE_PIXELS * zoom))
  camera.style.height = math.min(size.height, math.ceil(h * TILE_PIXELS * zoom))
  return frame
end

-- Beside the window, or on its left when the right side is off the screen.
local function place(card, player, window)
  local scale = player.display_scale
  local at = window.location or { x = 0, y = 0 }
  local x = at.x + (WINDOW_WIDTH + GAP) * scale
  if x + (CARD_SIZE.width + 24) * scale > player.display_resolution.width then
    x = math.max(0, at.x - (CARD_SIZE.width + 24 + GAP) * scale)
  end
  card.location = { x = x, y = at.y }
end

function preview.hide(player)
  local card = player.gui.screen[CARD]
  if card then card.destroy() end
end

function preview.show(player, window, design)
  preview.hide(player)
  local card = player.gui.screen.add {
    type = "frame", name = CARD, direction = "vertical", ignored_by_interaction = true,
    caption = { "seb-gui.design-heading", design.name, design.id, design.version },
  }
  preview.camera(card, player, design, CARD_SIZE)
  local prepared = design.prepared
  if prepared and prepared.ok then
    local w, h = design_text.size(prepared)
    local lines = { { "seb-gui.design-size", w, h }, design_text.parts(prepared), design_text.growth(prepared) }
    lines[#lines + 1] = design_text.pools(design)
    for _, caption in ipairs(lines) do
      local label = card.add { type = "label", caption = caption }
      label.style.single_line = false
      label.style.maximal_width = CARD_SIZE.width
    end
  end
  place(card, player, window)
end

return preview
