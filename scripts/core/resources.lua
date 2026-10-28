-- Looking at the ground for resources (depletion.lua). One engine count over
-- the names a look cares about, stopping at the first, instead of listing
-- every resource in the area: on a dense field that listing builds an entity
-- object per tile for a yes or a no.
--
-- The count is the engine's own rule, a resource whose collision box overlaps
-- the area. A resource that fits a tile stands in an area exactly when its
-- centre does, which is what a look means, so the count answers for it. A
-- bigger one (oil, lithium brine) also overlaps an area its edge only
-- touches: those few are listed and judged by their centre.

local geometry = require("scripts.core.geometry")

local resources = {}

-- Resource names by what a look counts, in two lists by size. Prototypes do
-- not change within a run, so each set is worked out once per load; nothing
-- here is saved.
local names_by_set = {}

local function set_key(categories, infinite)
  local list = {}
  for category in pairs(categories or {}) do list[#list + 1] = category end
  table.sort(list)
  return (categories and table.concat(list, ",") or "*") .. (infinite and "+" or "")
end

local function fits_a_tile(proto)
  local box = proto.collision_box
  return box.right_bottom.x - box.left_top.x <= 1 and box.right_bottom.y - box.left_top.y <= 1
end

local function names_of(categories, infinite)
  local names = { tile = {}, big = {} }
  for name, proto in pairs(prototypes.get_entity_filtered { { filter = "type", type = "resource" } }) do
    local mined = not categories or categories[proto.resource_category]
    if mined and (infinite or not proto.infinite_resource) then
      local list = fits_a_tile(proto) and names.tile or names.big
      list[#list + 1] = name
    end
  end
  return names
end

-- The names of the resources in `categories` (a set; nil for all of them),
-- the infinite ones too only when asked: they never run out.
function resources.names(categories, infinite)
  local key = set_key(categories, infinite)
  local names = names_by_set[key]
  if not names then
    names = names_of(categories, infinite)
    names_by_set[key] = names
  end
  return names
end

local function counted(surface, box, names)
  return #names > 0 and surface.count_entities_filtered { area = geometry.area(box), name = names, limit = 1 } > 0
end

local function centred(surface, box, names)
  if #names == 0 then return false end
  for _, resource in pairs(surface.find_entities_filtered { area = geometry.area(box), name = names }) do
    if geometry.contains_point(box, resource.position) then return true end
  end
  return false
end

-- Whether any such resource stands in the box.
function resources.left(surface, box, categories, infinite)
  local names = resources.names(categories, infinite)
  return counted(surface, box, names.tile) or centred(surface, box, names.big)
end

return resources
