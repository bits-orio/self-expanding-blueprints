-- Renaming a design. Sockets of other designs name the design they attach,
-- so a name it had before stays an alias they still find it by
-- (library.find); a blueprint registered under that name makes a new design,
-- as the name itself is free again. The design's mirror twin takes the name
-- too.

local library = require("scripts.core.library")

local naming = {}

-- Renames `design` to `name` (trimmed); the design, or nil and a reason.
function naming.rename(design, name)
  name = (name or ""):match("^%s*(.-)%s*$")
  if name == "" then return nil, "name-empty" end
  if name == design.name then return design end
  local lib = library.of(design.force_index)
  if lib.by_name[name] then return nil, "name-taken" end
  lib.aliases = lib.aliases or {}
  lib.aliases[name] = nil
  lib.aliases[design.name] = design.id
  lib.by_name[design.name] = nil
  lib.by_name[name] = design.id
  design.name = name
  local twin = design.twin_id and library.get(design.force_index, design.twin_id)
  if twin then twin.name = name end
  return design
end

return naming
