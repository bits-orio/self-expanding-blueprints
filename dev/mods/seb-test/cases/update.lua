-- update.lua: a copy moves to its design's newest version in place.
--   kept:     the part both versions share is the same entity afterwards
--   removed:  a part the new version dropped is deconstructed
--   added:    a part only the new version has is built by robots
--   refused:  a copy whose new footprint would cover someone else's
--             building is not updated
--   research: a design naming a technology updates its copies when the
--             force finishes that research

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "update" }

local REGION = 45
local V1 = { rig.panel(1.5, 1.5), rig.panel(4.5, 1.5) }
local V2 = { rig.panel(1.5, 1.5), rig.panel(1.5, 4.5) }

local function panels(surface)
  local o = rig.region(REGION)
  local list = surface.find_entities_filtered { area = { { o.x - 5, o.y - 5 }, { o.x + 15, o.y + 25 } }, name = "solar-panel" }
  table.sort(list, function(a, b) return a.position.x < b.position.x or (a.position.x == b.position.x and a.position.y < b.position.y) end)
  return list
end

function case.setup(surface)
  rig.site(surface, REGION)
  storage.update = { design = rig.design(V1, "Update cell"), researched = rig.design(V1, "Research cell") }
end

function case.start()
  local u = storage.update
  local o = rig.region(REGION)
  u.copy = rig.call("stamp", { force = rig.FORCE, surface = game.surfaces.nauvis, design = u.design, position = rig.offset(o, 0.5, 0.5) })
  u.blocked = rig.call("stamp", { force = rig.FORCE, surface = game.surfaces.nauvis, design = u.design, position = rig.offset(o, 0.5, 12.5) })
  u.research_copy = rig.call("stamp", { force = rig.FORCE, surface = game.surfaces.nauvis, design = u.researched, position = rig.offset(o, 0.5, -15.5) })
  check.truthy("update copies stamped", u.copy and u.blocked)
end

local function built(surface)
  local u = storage.update
  local list = panels(surface)
  check.eq("update v1 built", #list, 4)
  u.kept = list[1].unit_number                      -- the westmost, top panel of the first copy
  u.kept_position = list[1].position
  -- Someone's chest where the second copy's v2 would reach.
  local blocked = rig.call("get_instance", u.blocked)
  local fp = blocked.footprint
  surface.create_entity { name = "iron-chest", position = { fp.left + 1.5, fp.bottom + 1.5 }, force = rig.FORCE }
  local id, reason = rig.call("register_design", rig.FORCE, rig.blueprint(V2, { label = "Update cell" }))
  check.eq("update v2 registered as the next version", id, u.design)
  local ok, why = rig.call("update_instance", u.copy)
  check.eq("update accepted", ok, true, why)
  local refused, because = rig.call("update_instance", u.blocked)
  check.eq("update refused over a foreign building", refused, false)
  check.eq("update refusal reason", because, "building")
  local again, up = rig.call("update_instance", u.copy)
  check.eq("update twice is a no-op", up == "up-to-date" or again == false, true)
  -- Research: the new version waits for steel processing.
  rig.call("register_design", rig.FORCE, rig.blueprint(V2, { label = "Research cell" }))
  check.eq("update research named", rig.call("set_upgrade_research", rig.FORCE, u.researched, "steel-processing"), true)
  local before = rig.call("get_instance", u.research_copy)
  check.eq("update research copy waits for the research", before and before.version, 1)
  game.forces[rig.FORCE].technologies["steel-processing"].researched = true
end

local function updated(surface)
  local u = storage.update
  local inst = rig.call("get_instance", u.copy)
  check.eq("update copy is version 2", inst and inst.version, 2)
  check.eq("update copy complete", inst and inst.state, "complete")
  check.eq("update copy holds two entities", inst and inst.entity_count, 2)
  local kept, added, dropped = false, false, true
  for _, panel in pairs(panels(surface)) do
    local p = panel.position
    if panel.unit_number == u.kept then kept = true end
    if p.x == u.kept_position.x and p.y == u.kept_position.y + 3 then added = true end
    if p.x == u.kept_position.x + 3 and p.y == u.kept_position.y then dropped = false end
  end
  check.truthy("update kept the shared panel", kept)
  check.truthy("update built the new panel", added)
  check.truthy("update removed the dropped panel", dropped)
  local researched = rig.call("get_instance", u.research_copy)
  check.eq("update research moved the copy to version 2", researched and researched.version, 2)
end

case.checks = { [1200] = built, [3000] = updated }

return case
