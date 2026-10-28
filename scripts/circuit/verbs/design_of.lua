-- Which design a request names: the Design signal's number, or else the
-- first design of the builder's force whose icon is a signal on the input
-- (DESIGN.md: "design number, or a match by icon").

local library = require("scripts.core.library")

local function by_icon(force_index, input)
  for _, design in ipairs(library.list(force_index)) do
    local icon = design.icon
    local bucket = icon and input[icon.type or "item"]
    -- Through get: a design a mod change left stale is prepared again first.
    if bucket and bucket[icon.name] then return library.get(force_index, design.id) end
  end
end

return function(b, input)
  local force_index = b.entity.force.index
  local id = input.virtual["seb-design"]
  if id then return library.get(force_index, id) end
  return by_icon(force_index, input)
end
