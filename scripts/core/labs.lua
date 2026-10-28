-- The mod's hidden lab surfaces: the calibration lab (calibration.lua) and
-- the gallery of design pictures (gallery.lua). Both are floored with lab
-- tiles and nothing else, always day, hidden from every force (also forces
-- made later), and kept out of Land Title Registry's claims.

local const = require("scripts.const")
local geometry = require("scripts.core.geometry")
local budget = require("scripts.core.budget")

local labs = {}

local NAMES = { const.CALIBRATION_SURFACE, const.GALLERY_SURFACE }

-- A new surface is visible to every force, in remote view's surface list
-- too.
local function hide(lab)
  for _, force in pairs(game.forces) do
    if not force.get_surface_hidden(lab) then force.set_surface_hidden(lab, true) end
  end
end

-- Land Title Registry lays its grid on every surface unless told otherwise
-- (with Multi-Team Support it only claims team surfaces anyway). Checked each
-- time a lab is used, so a registry added to a save with a lab also learns.
local function exclude_from_claims(lab)
  local ltr = remote.interfaces["land-title-registry"]
  if not (ltr and ltr.set_surface_enabled) then return end
  if ltr.get_surface_enabled and not remote.call("land-title-registry", "get_surface_enabled", lab) then return end
  remote.call("land-title-registry", "set_surface_enabled", lab, false)
end

-- Map generation places nothing on a lab: no trees, rocks, ore or nests.
local function empty_map(settings)
  local out = {
    default_enable_all_autoplace_controls = false, no_enemies_mode = true,
    autoplace_settings = {
      entity = { treat_missing_as_default = false, settings = {} },
      decorative = { treat_missing_as_default = false, settings = {} },
    },
  }
  for k, v in pairs(settings or {}) do out[k] = v end
  return out
end

-- The lab named `name`, made on first use (`settings`: extra map gen
-- settings, such as a size).
function labs.surface(name, settings)
  local lab = game.get_surface(name)
  if not lab then
    lab = game.create_surface(name, empty_map(settings))
    lab.generate_with_lab_tiles = true
    lab.always_day = true
    lab.show_clouds = false
  end
  exclude_from_claims(lab)
  hide(lab)
  return lab
end

function labs.on_force_created(event)
  for _, name in ipairs(NAMES) do
    local lab = game.get_surface(name)
    if lab then event.force.set_surface_hidden(lab, true) end
  end
end

-- Makes the chunks `box` touches exist now, for a design of the force
-- `force_index`. Only those are asked for (the engine lays out three more
-- around each on a lab-tile surface): the labs are shared by every team
-- and kept in the save. The force pays for the chunks it needs made
-- (budget.lua), as a design with a few parts far apart spans hundreds.
function labs.generate(lab, box, force_index)
  local missing = 0
  geometry.each_chunk(box, function(cx, cy)
    if not lab.is_chunk_generated({ cx, cy }) then
      lab.request_to_generate_chunks(geometry.chunk_center(cx, cy), 0)
      missing = missing + 1
    end
  end)
  if missing == 0 then return end
  lab.force_generate_chunk_requests()
  budget.charge(force_index, missing * budget.COST.lab_chunk)
end

return labs
