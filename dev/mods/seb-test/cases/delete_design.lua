-- delete_design.lua: deleting a design ends its projects, its mirror twin's
-- included, and forgets their copies (lifecycle.lua): their buildings stay,
-- their ground is free again, and another design starts there.

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "delete_design" }

local REGION = 185
local D = defines.direction

local function start(surface, design, at, extra)
  local params = {
    force = rig.FORCE, surface = surface, design = design, point = at, directions = { D.east },
    max_instances = 3, open_early = true, max_building = 8, charted_only = false,
  }
  for k, v in pairs(extra or {}) do params[k] = v end
  return rig.call("start_project", params)
end

function case.setup(surface)
  local o = rig.site(surface, REGION)
  storage.delete_design = {
    origin = o,
    doomed = rig.design({ rig.panel(1.5, 1.5) }, "Delete doomed panel"),
    kept = rig.design({ rig.panel(1.5, 1.5), rig.panel(4.5, 1.5) }, "Delete kept pair"),
  }
end

function case.start(surface)
  local d = storage.delete_design
  d.plain = start(surface, d.doomed, rig.offset(d.origin, 1.5, 1.5))
  d.mirrored = start(surface, d.doomed, rig.offset(d.origin, 1.5, 11.5), { mirrored = true })
  check.truthy("delete_design projects start", d.plain and d.mirrored)
end

local function deleted()
  local d, surface = storage.delete_design, game.surfaces.nauvis
  local copies = {}
  for _, project in ipairs({ d.plain, d.mirrored }) do
    for _, inst in ipairs(rig.instances_of(project)) do copies[#copies + 1] = inst.id end
  end
  check.eq("delete_design grew both projects", #copies, 6)
  check.eq("delete_design deletes", rig.call("delete_design", rig.FORCE, d.doomed), true)
  check.truthy("delete_design forgets its projects",
    rig.call("get_project", d.plain) == nil and rig.call("get_project", d.mirrored) == nil)
  local left = 0
  for _, id in ipairs(copies) do if rig.call("get_instance", id) then left = left + 1 end end
  check.eq("delete_design forgets its copies", left, 0)
  check.eq("delete_design leaves their buildings",
    rig.count(surface, rig.box(d.origin, -1, -1, 30, 20), "solar-panel"), 6)
  local listed = false
  for _, row in ipairs(rig.call("list_designs", rig.FORCE)) do
    if row.name == "Delete doomed panel" then listed = true end
  end
  check.eq("delete_design takes it off the list", listed, false)
  local again, why = rig.call("delete_design", rig.FORCE, d.doomed)
  check.truthy("delete_design refuses a design that is gone", again == false and why == "unknown-design", why)
  local id, reason = start(surface, d.kept, rig.offset(d.origin, 1.5, 1.5), { max_instances = 1 })
  check.truthy("delete_design frees the ground for another design", id, reason)
end

case.checks = { [1500] = deleted }

return case
