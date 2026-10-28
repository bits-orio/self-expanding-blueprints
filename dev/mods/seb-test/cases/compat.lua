-- compat.lua: the sibling mods, each stood in for by an interface of the
-- test mod's own.
--   mts:  Multi-Team Support recycles a released team's force, so the mod
--         drops that force's designs and instance records on mts-v1's
--         on_team_released
--   ltr:  Land Title Registry never claims the calibration lab, also when the
--         registry turns it back on (added to a save that has a lab); a
--         stamp its blocker refuses says "outside held land"

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "compat" }

local REGION = 20
local RELEASED = script.generate_event_name()

remote.add_interface("mts-v1", {
  get_event_id = function(name)
    if name == "on_team_released" then return RELEASED end
  end,
})

remote.add_interface("land-title-registry", {
  set_surface_enabled = function(surface, enabled)
    storage.ltr_enabled = storage.ltr_enabled or {}
    storage.ltr_enabled[surface.name] = enabled
  end,
  get_surface_enabled = function(surface)
    return not (storage.ltr_enabled and storage.ltr_enabled[surface.name] == false)
  end,
})

local function lab_excluded()
  return storage.ltr_enabled ~= nil and storage.ltr_enabled["seb-calibration"] == false
end

local function ltr_case()
  check.truthy("compat calibration lab excluded from claims", lab_excluded(), check.show(storage.ltr_enabled))
  storage.ltr_enabled["seb-calibration"] = true
  rig.design({ rig.panel(1.5, 1.5) }, "Compat recalibrated")
  check.truthy("compat lab excluded again at the next calibration", lab_excluded(), check.show(storage.ltr_enabled))
end

function case.setup(surface)
  ltr_case()
  local o = rig.region(REGION)
  rig.floor(surface, rig.box(o, -10, -10, 30, 30))
  local team = game.create_force("seb-test-team")
  local design = rig.call("register_design", team, rig.blueprint({ rig.panel(1.5, 1.5) }, { label = "Team panel" }))
  local id, reason = rig.call("stamp", { force = team, surface = surface, design = design, position = rig.offset(o, 0, 0) })
  check.truthy("compat team stamp", id, reason)
  script.raise_event(RELEASED, { force_name = team.name })
  check.eq("compat released team's designs dropped", #rig.call("list_designs", team), 0)
  check.eq("compat released team's instances dropped", rig.call("get_instance", id), nil)
  -- A registry blocker in a part's way: the refusal says "outside held land".
  local held = rig.offset(o, 10.5, 10.5)
  surface.create_entity { name = "ltr-cell-wilderness", position = held, force = "neutral" }
  local refused, why = rig.call("stamp", {
    force = rig.FORCE, surface = surface, design = rig.design({ rig.panel(1.5, 1.5) }, "Compat held"), position = held,
  })
  check.eq("compat held land refuses the stamp", refused, nil)
  check.eq("compat held land names the reason", why, "held-land")
end

return case
