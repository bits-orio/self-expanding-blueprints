-- Cleanup when the world changes under the registry: a surface deleted or
-- cleared, forces merged, a team released. Records go; built entities stay
-- in the world.

local projects = require("scripts.core.projects")
local instances = require("scripts.core.instances")
local footprints = require("scripts.core.footprints")
local library = require("scripts.core.library")
local gallery = require("scripts.core.gallery")
local budget = require("scripts.core.budget")
local pace = require("scripts.core.pace")
local limits = require("scripts.core.limits")
local retry = require("scripts.core.retry")
local builder = require("scripts.circuit.builder")

local lifecycle = {}

-- dropped(forces): set by control.lua so open windows redraw; dropping raises
-- no project or design event of its own. `forces` is the set of force indexes
-- that lost a project, or nil when anyone's window may be stale.
lifecycle.hooks = {}

local function dropped(forces)
  if lifecycle.hooks.dropped then lifecycle.hooks.dropped(forces) end
end

-- Registrations whose instance is gone would only be ignored later; drop them now.
local function sweep_registrations()
  for _, regs in pairs({ storage.ghost_regs, storage.entity_regs }) do
    for reg, id in pairs(regs) do
      if not storage.instances[id] then regs[reg] = nil end
    end
  end
end

function lifecycle.drop_surface(surface_index)
  builder.drop_surface(surface_index)
  gallery.forget_surface(surface_index)
  local lost = projects.drop_where(function(project) return project.surface_index == surface_index end)
  instances.drop_where(function(instance) return instance.surface_index == surface_index end)
  footprints.drop_surface(surface_index)
  retry.drop_surface(surface_index)
  storage.chunk_waits[surface_index] = nil
  -- no sweep: every registered object on the surface fires on_object_destroyed
  -- and removes its own entry
  if next(lost) then dropped(lost) end
end

-- A design deleted from its team's library: its projects end and are
-- forgotten, and so are its copies, whose ground is free again. What they
-- built stays in the world, as for a dropped surface or force.
library.hooks.deleted = function(design)
  local force_index, id = design.force_index, design.id
  local function of_design(record) return record.force_index == force_index and record.design_id == id end
  projects.drop_where(of_design)
  instances.drop_where(of_design)
  sweep_registrations()
  -- The list of designs changed too: whole windows redraw.
  dropped(nil)
end

-- The force's builders end their requests first, so none runs on against
-- records that are gone. Its share of server time (and its projects' line
-- for it) and its own limits go too: a new force may get its index.
function lifecycle.drop_force(force_index)
  builder.drop_force(force_index)
  projects.drop_where(function(project) return project.force_index == force_index end)
  instances.drop_where(function(instance) return instance.force_index == force_index end)
  library.drop_force(force_index)
  budget.drop_force(force_index)
  pace.drop_force(force_index)
  limits.clear(force_index)
  sweep_registrations()
  -- A merge moves the players without on_player_changed_force: any window
  -- may now show the dropped force's records.
  dropped(nil)
end

return lifecycle
