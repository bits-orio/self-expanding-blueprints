-- What the overlay's marks share (overlay.lua for copies, marks.lua for
-- projects): their colours, the fields of every object a force sees, and
-- how a list of objects goes.

local draw = {}

draw.COLOR = {
  building = { r = 0.25, g = 0.60, b = 1.00, a = 0.85 },
  stalled = { r = 1.00, g = 0.60, b = 0.10, a = 0.90 },
  incomplete = { r = 0.85, g = 0.30, b = 0.85, a = 0.90 },
  retiring = { r = 0.70, g = 0.25, b = 0.25, a = 0.85 },
  ore = { r = 0.95, g = 0.70, b = 0.25, a = 0.80 },
  planned = { r = 0.55, g = 0.80, b = 1.00, a = 0.70 },
  open = { r = 0.30, g = 0.85, b = 0.40, a = 0.90 },
  waiting = { r = 1.00, g = 0.85, b = 0.20, a = 0.90 },
  blocked = { r = 0.95, g = 0.25, b = 0.20, a = 0.95 },
  next = { r = 0.55, g = 0.95, b = 0.60, a = 0.55 },
}

function draw.destroy_all(objects)
  for _, object in pairs(objects or {}) do
    if object.valid then object.destroy() end
  end
end

-- On `surface`, for the force's eyes only.
function draw.base(surface, force_index)
  return { surface = surface, forces = { force_index } }
end

function draw.with(base, fields)
  for k, v in pairs(base) do fields[k] = fields[k] or v end
  return fields
end

-- An arrow on a socket, pointing the way the copy there would face.
function draw.arrow(objects, base, socket, color)
  objects[#objects + 1] = rendering.draw_sprite(draw.with(base, {
    sprite = "seb-overlay-arrow", tint = color, x_scale = 0.6, y_scale = 0.6,
    orientation = (socket.direction or 0) / 16, target = socket.position,
  }))
end

return draw
