-- How the remote interface finds what a caller names: forces and surfaces
-- as an object, a name or an index; designs by id or name; and what kind of
-- Lua object a value is.

local library = require("scripts.core.library")

local lookup = {}

-- A name or index the engine refuses (NaN, -1, 1e300) is just unknown.
local function looked_up(map, key)
  local ok, found = pcall(function() return map[key] end)
  return ok and found or nil
end

-- A name, an index or a valid object of the given class.
local function object_of(value, map, class)
  if type(value) == "string" or type(value) == "number" then return looked_up(map, value) end
  if type(value) == "userdata" and value.valid and value.object_name == class then return value end
end

function lookup.force(force)
  return object_of(force, game.forces, "LuaForce")
end

function lookup.surface(surface)
  return object_of(surface, game.surfaces, "LuaSurface")
end

function lookup.design(force_index, design)
  if type(design) == "string" then return library.find(force_index, design) end
  return library.get(force_index, design)
end

-- The object name of a valid Lua object passed in, or nil for anything else.
function lookup.object_name(value)
  if type(value) ~= "userdata" then return nil end
  local ok, name = pcall(function() return value.valid and value.object_name end)
  return ok and name or nil
end

return lookup
