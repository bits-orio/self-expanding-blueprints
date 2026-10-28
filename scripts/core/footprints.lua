-- The overlap index: which instances occupy which chunks of each surface,
-- kept in step with storage.instances as instances are added and retired.

local geometry = require("scripts.core.geometry")

local footprints = {}

function footprints.init_storage()
  storage.footprints = storage.footprints or {}
end

local function buckets_of(surface_index)
  local per_surface = storage.footprints[surface_index]
  if not per_surface then
    per_surface = {}
    storage.footprints[surface_index] = per_surface
  end
  return per_surface
end

function footprints.add(instance)
  local per_surface = buckets_of(instance.surface_index)
  geometry.each_chunk(instance.footprint, function(cx, cy)
    local key = geometry.chunk_key(cx, cy)
    local bucket = per_surface[key]
    if not bucket then
      bucket = {}
      per_surface[key] = bucket
    end
    bucket[instance.id] = true
  end)
end

function footprints.remove(instance)
  local per_surface = storage.footprints[instance.surface_index]
  if not per_surface then return end
  geometry.each_chunk(instance.footprint, function(cx, cy)
    local key = geometry.chunk_key(cx, cy)
    local bucket = per_surface[key]
    if bucket then
      bucket[instance.id] = nil
      if next(bucket) == nil then per_surface[key] = nil end
    end
  end)
end

-- Ids of the instances whose footprint overlaps `box`, in ascending order.
function footprints.overlapping(surface_index, box)
  local per_surface = storage.footprints[surface_index]
  if not per_surface then return {} end
  local seen, found = {}, {}
  geometry.each_chunk(box, function(cx, cy)
    for id in pairs(per_surface[geometry.chunk_key(cx, cy)] or {}) do
      if not seen[id] then
        seen[id] = true
        local instance = storage.instances[id]
        if instance and geometry.overlaps(instance.footprint, box) then found[#found + 1] = id end
      end
    end
  end)
  table.sort(found)
  return found
end

-- Ids of the instances whose footprint holds the position.
function footprints.at(surface_index, position)
  local box = geometry.box(position.x, position.y, position.x + 1e-3, position.y + 1e-3)
  return footprints.overlapping(surface_index, box)
end

function footprints.drop_surface(surface_index)
  storage.footprints[surface_index] = nil
end

return footprints
