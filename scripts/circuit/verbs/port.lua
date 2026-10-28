-- A copy's port (DESIGN.md "Port"): the combinator a design marks with a
-- port marker, the copy's circuit mailbox. Read and Write find it by the
-- copy number in the Instance signal.

local port = {}

local COMBINATORS = { "constant-combinator", "arithmetic-combinator", "decider-combinator", "selector-combinator" }

-- The built combinator of the copy under its port marker, or nil and a
-- reason. Found where the marker is, not among all of the copy's parts, so
-- a request costs the same for a copy of any size.
function port.of(b, input)
  local instance = storage.instances[input.virtual["seb-instance"] or 0]
  if not (instance and instance.force_index == b.entity.force.index) then return nil, "not-found" end
  local at, surface = instance.port, game.surfaces[instance.surface_index]
  if not (at and surface) then return nil, "not-found" end
  for _, entity in pairs(surface.find_entities_filtered { position = at, type = COMBINATORS }) do
    if instance.entities[entity.unit_number] == entity then return entity end
  end
  return nil, "not-found"
end

return port
