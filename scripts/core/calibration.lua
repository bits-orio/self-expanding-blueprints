-- Calibration: where build_blueprint puts a design's blueprint origin, per
-- build direction, measured instead of derived. The design's stamping copy
-- carries an anchor entity at a known blueprint position; stamping that copy
-- at the origin of a hidden lab surface and reading where the anchor's ghost
-- landed gives offsets[d], with world = P + offsets[d] + rotate(bp, d).
-- Ghosts made here never raise events (raise_built = false) and are
-- destroyed in the same tick.
--
-- build_blueprint centres a stamp on its build position (spike S1: the
-- rotated centre of the tile bounds lands there), so a copy built at the lab
-- origin lands around it however far its parts sit from their blueprint
-- origin. The lab work is sized by the copy's own reach: a design with a
-- part 4,000 tiles from its origin costs what a near one does.

local const = require("scripts.const")
local geometry = require("scripts.core.geometry")
local labs = require("scripts.core.labs")

local calibration = {}

-- Tiles of slack around where the copy lands: the engine rounds the centre
-- onto the build grid (half a tile, a tile for rail designs).
local MARGIN = 8

-- The lab area a copy covers in any direction when built at the origin.
local function landing(reach)
  local half = math.ceil(math.max(reach.right - reach.left, reach.bottom - reach.top) / 2) + MARGIN
  return geometry.box(-half, -half, half, half)
end

local function clear(lab, box)
  for _, entity in pairs(lab.find_entities_filtered { area = geometry.area(box) }) do
    if entity.valid and entity.type ~= "character" then entity.destroy() end
  end
end

local function anchor_position(ghosts)
  for _, ghost in pairs(ghosts) do
    if ghost.valid and ghost.type == "entity-ghost" and ghost.ghost_name == const.ANCHOR then return ghost.position end
  end
end

-- offsets[d] for the four cardinal directions, or nil if the anchor never
-- landed. `reach` is the box everything in the copy covers, in blueprint
-- coordinates (prepare.lua).
function calibration.measure(stack, anchor_bp, force, reach)
  local lab = labs.surface(const.CALIBRATION_SURFACE, { width = 2048, height = 2048 })
  local area = landing(reach)
  labs.generate(lab, area, force.index)
  local offsets = {}
  for _, d in ipairs(geometry.CARDINALS) do
    clear(lab, area)
    local ghosts = stack.build_blueprint {
      surface = lab, force = force, position = { 0, 0 }, direction = d,
      build_mode = defines.build_mode.forced, raise_built = false,
    }
    local landed = anchor_position(ghosts)
    if not landed then
      clear(lab, area)
      return nil
    end
    local r = geometry.rotate(anchor_bp, d)
    offsets[d] = { x = landed.x - r.x, y = landed.y - r.y }
  end
  clear(lab, area)
  return offsets
end

return calibration
