-- Sprites the overlay draws with rendering.draw_sprite (tinted at draw time),
-- and the help pictures.

local GRAPHICS = require("scripts.const").GRAPHICS

data:extend({
  { type = "sprite", name = "seb-overlay-arrow", filename = GRAPHICS .. "overlay-arrow.png", size = 64 },
  { type = "sprite", name = "seb-overlay-blocked", filename = GRAPHICS .. "overlay-blocked.png", size = 64 },
  -- "How growing works" (scripts/gui/help_view.lua): a picture per marker.
  -- "gui" keeps the transparent margins (a cropped sprite is stretched back
  -- to the widget, out of proportion) and the pixels uncompressed.
  { type = "sprite", name = "seb-help-growth", filename = GRAPHICS .. "help-growth.png", width = 400, height = 80, flags = { "gui" } },
  { type = "sprite", name = "seb-help-sensor", filename = GRAPHICS .. "help-sensor.png", width = 400, height = 80, flags = { "gui" } },
  { type = "sprite", name = "seb-help-probe", filename = GRAPHICS .. "help-probe.png", width = 400, height = 112, flags = { "gui" } },
  { type = "sprite", name = "seb-help-port", filename = GRAPHICS .. "help-port.png", width = 400, height = 80, flags = { "gui" } },
  { type = "sprite", name = "seb-help-clear", filename = GRAPHICS .. "help-clear.png", width = 400, height = 80, flags = { "gui" } },
})
