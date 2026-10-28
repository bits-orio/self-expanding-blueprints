-- Capture: the rectangle X, Y, W, H becomes a new design ("Captured N"),
-- everything of the builder's own force in it, tiles included (its
-- friends' buildings stay theirs). DONE with the new design's number in the
-- Design signal; ERR "not found" when there is nothing to capture, or the
-- limit error past the team's designs or parts (library.lua). A new design
-- is exported, calibrated and pictured in the same tick at about 35
-- microseconds per floor tile (spike S6), so the area is held to 64 x 64
-- tiles, and the capture waits (accepted, running) until the team's share
-- of server time allows it (D44).

local const = require("scripts.const")
local budget = require("scripts.core.budget")
local library = require("scripts.core.library")
local previews = require("scripts.core.previews")
local answer = require("scripts.circuit.answer")

local capture = {}

local MAX_TILES = 64 * 64

function capture.start(b, request, input)
  local area = answer.area(b, input, MAX_TILES)
  if not area then return answer.fail(b, "invalid") end
  -- Refused before the blueprint is made: a full library takes no new design.
  if library.full(b.force_index) then return answer.fail(b, const.REASON.too_many_designs) end
  request.area = area
  capture.tick(b, request)
end

local function wires_between(wires, foreign)
  local kept = {}
  for _, wire in ipairs(wires or {}) do
    if not (foreign[wire[1]] or foreign[wire[3]]) then kept[#kept + 1] = wire end
  end
  return kept[1] and kept or nil
end

-- create_blueprint takes the force's friends' buildings too; `sources`
-- names what each blueprint entity was made from.
local function keep_own(stack, sources, force_index)
  local foreign = {}
  for number, entity in pairs(sources) do
    if entity.valid and entity.force_index ~= force_index then foreign[number] = true end
  end
  if not next(foreign) then return end
  local kept = {}
  for _, e in ipairs(stack.get_blueprint_entities() or {}) do
    if not foreign[e.entity_number] then
      e.wires = wires_between(e.wires, foreign)
      kept[#kept + 1] = e
    end
  end
  stack.set_blueprint_entities(kept)
  -- The icons were picked from everything; an empty blueprint has none.
  if stack.is_blueprint_setup() then stack.preview_icons = stack.default_icons end
end

-- The blueprint of the area, in a fresh inventory the caller destroys.
local function blueprint_of(b, area)
  previews.make_room(b.entity.surface_index, area)
  local inventory = game.create_inventory(1)
  local stack = inventory[1]
  stack.set_stack { name = "blueprint" }
  local sources = stack.create_blueprint {
    surface = b.entity.surface, force = b.entity.force, area = { { area.left, area.top }, { area.right, area.bottom } },
    always_include_tiles = true, include_modules = true,
  }
  keep_own(stack, sources, b.force_index)
  return inventory, stack
end

function capture.tick(b, request)
  if not budget.ready(b.force_index) then return end
  local area = request.area
  local inventory, stack = blueprint_of(b, area)
  if not stack.is_blueprint_setup() then
    inventory.destroy()
    return answer.fail(b, "not-found")
  end
  local number = (storage.captures or 0) + 1
  local design, reason = library.register_string(b.force_index, stack.export_stack(), "Captured " .. number)
  inventory.destroy()
  budget.charge(b.force_index, (area.right - area.left) * (area.bottom - area.top) * budget.COST.area_tile)
  if not design then return answer.fail(b, reason) end
  storage.captures = number
  request.design_id = design.id
  answer.done(b, { [answer.virtual("seb-design")] = design.id })
end

return capture
