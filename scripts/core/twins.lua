-- A design's mirror twin: the design as a flipped paste grows it, drawn by
-- mirror.lua and kept as a hidden design of the library, so that stamps,
-- calibration, updates and sensors treat it as any design. Made the first
-- time a flipped paste needs it, remade whenever the design takes a new
-- version (so a flipped project's copies can be updated as the others), and
-- deleted with the design. Players never see it: its projects show under the
-- design, marked flipped.

local library = require("scripts.core.library")
local mirror = require("scripts.core.mirror")

local twins = {}

-- How mirror.lua draws a twin; a twin drawn another way is drawn again.
-- 2: snapped blueprints turn over inside their grid cell.
local FORMAT = 2

-- The design a twin mirrors, or the design itself.
function twins.origin(design)
  return design.mirror_of and library.get(design.force_index, design.mirror_of) or design
end

-- The id of the design a project or copy shows under: its own, or for a
-- twin's, the design it mirrors.
function twins.origin_id(force_index, design_id)
  local design = library.get(force_index, design_id)
  return design and design.mirror_of or design_id
end

-- `design`'s twin, of its current version; nil and a reason when the design
-- cannot be mirrored (and the part type that stops it) or the library is full.
-- A twin is its own: the mirror of a mirror is not made.
function twins.of(design)
  if design.mirror_of then return design end
  local twin = design.twin_id and library.get(design.force_index, design.twin_id)
  if twin and twin.mirror_version == design.version and twin.mirror_format == FORMAT then return twin end
  local refused
  local function write(stack)
    local ok, kind = mirror.write(stack, library.stack(design))
    refused = kind
    return ok, "cannot-mirror"
  end
  local made, why = library.register_hidden(design.force_index, design.name, write, twin)
  if not made then return nil, why, refused end
  made.mirror_of, made.mirror_version, made.upgrade_on = design.id, design.version, design.upgrade_on
  made.mirror_format = FORMAT
  design.twin_id = made.id
  return made
end

-- A design with a twin took a new version: the twin follows at once, so its
-- copies show as outdated as the design's do.
library.hooks.new_version = function(design)
  if design.twin_id then twins.of(design) end
end

return twins
