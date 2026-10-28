-- frontier.lua: how open sockets wait, close and resume.
--   parking:  a socket no robots reach is parked; the rest of the frontier
--             still fills, and parked sockets resume once coverage grows
--   retired:  a parent retired from its completion event opens nothing; one
--             retired while its sockets queue closes them as parent-retired
--   update:   a design updated mid-project still abuts the older copies
--   starved:  on_materials_missing fires once per wait, not on every retry
--   stalled:  a stamp robots cannot finish stalls with the reason why
--   map:      a seed on land not generated yet waits for the map, and the
--             chunk's generation (not a timer) wakes it

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "frontier" }

local PARK_REGION, RETIRE_REGION, STARVED_REGION = 17, 18, 19
local UNGENERATED_REGION = 99   -- far from every floored region: no chunks there
local CELL = { rig.panel(1.5, 1.5) }
local SMALL = { { name = "accumulator", position = { x = 1, y = 1 } } }
-- The site's network (roboport at x = -25) covers x < 30: three 3-wide
-- columns from x = 20 fit; the area runs to x = 38, so three more wait for
-- the second network.
local COVERED, MORE, ROWS = 3, 3, 4

local function start(design, extra)
  local params = { force = rig.FORCE, surface = game.surfaces.nauvis, design = design, charted_only = false }
  for k, v in pairs(extra) do params[k] = v end
  local id, reason = rig.call("start_project", params)
  check.truthy("frontier start design " .. design, id, reason)
  return id
end

function case.setup(surface)
  local f = { missing = 0 }
  storage.frontier = f
  rig.site(surface, PARK_REGION)
  rig.site(surface, RETIRE_REGION)
  local s = rig.region(STARVED_REGION)
  rig.floor(surface, rig.box(s, -60, -60, 60, 60))
  rig.network(surface, rig.offset(s, -25, -25), { { "iron-chest", 1 } })
  f.cell = rig.design(CELL, "Frontier cell")
  f.grows = rig.design(CELL, "Frontier grows")
  f.lamp = rig.design({ { name = "small-lamp", position = { x = 0.5, y = 0.5 } } }, "Frontier lamp")
  f.unsupplied = rig.call("stamp", { force = rig.FORCE, surface = surface, design = f.lamp, position = rig.offset(s, 0, 20) })
  f.unreached = rig.call("stamp", { force = rig.FORCE, surface = surface, design = f.lamp, position = rig.offset(s, 50, 50) })
end

function case.start()
  local f, p, r = storage.frontier, rig.region(PARK_REGION), rig.region(RETIRE_REGION)
  f.park = start(f.cell, { area = rig.box(p, 20, 0, 20 + 3 * (COVERED + MORE), 3 * ROWS) })
  f.at_event = start(f.cell, { build_position = rig.offset(r, 0, 0), max_instances = 3 })
  f.queued = start(f.cell, { build_position = rig.offset(r, 0, 20), max_instances = 3 })
  f.update = start(f.grows, { build_position = rig.offset(r, 20, 0), directions = { defines.direction.east }, max_instances = 2 })
  f.starved = start(f.lamp, { build_position = rig.offset(rig.region(STARVED_REGION), 0, 0) })
  f.ungenerated = start(f.lamp, { build_position = rig.region(UNGENERATED_REGION), max_instances = 1, materials = false })
end

-- Reacts to the first completion of each scenario's seed.
local REACT = {
  at_event = function(payload) rig.call("remove_instance", payload.instance_id) end,
  queued = function(payload)
    rig.call("pause_project", payload.project_id)
    storage.frontier.queued_seed = payload.instance_id
  end,
  update = function() rig.design(SMALL, "Frontier grows") end,
}

function case.on_event(name, payload)
  local f = storage.frontier
  if not f then return end
  if name == "on_materials_missing" and payload.project_id == f.starved then f.missing = f.missing + 1 end
  -- Remote stamps complete too, with no project.
  if name ~= "on_instance_completed" or not payload.project_id then return end
  for key, react in pairs(REACT) do
    if payload.project_id == f[key] and not f["reacted_" .. key] then
      f["reacted_" .. key] = true
      react(payload)
    end
  end
end

local function project(id)
  return rig.call("get_project", id) or {}
end

local function parked_check(surface)
  local f = storage.frontier
  local p = project(f.park)
  check.eq("frontier parking fills what robots reach", p.count, COVERED * ROWS)
  check.eq("frontier parking parks the sockets beyond", p.parked, ROWS)
  check.eq("frontier parking keeps growing", p.state, "growing")
  check.eq("frontier parking holds no gate", p.gate, nil)
  local drawn = rig.drawn(surface, rig.box(rig.region(PARK_REGION), 15, -5, 45, 20))
  check.same("frontier parked sockets drawn waiting", { drawn["seb-overlay-arrow"], drawn.text }, { ROWS, ROWS })
  rig.network(surface, rig.offset(rig.region(PARK_REGION), 40, 20))
  -- Retire the paused project's seed while its sockets wait, then resume it.
  if f.queued_seed then rig.call("remove_instance", f.queued_seed) end
  rig.call("resume_project", f.queued)
end

local function final_check()
  local f = storage.frontier
  local p = project(f.park)
  check.eq("frontier parked sockets resume with coverage", p.count, (COVERED + MORE) * ROWS)
  check.eq("frontier parking ends finished", p.state, "finished")
  local at_event, queued = project(f.at_event), project(f.queued)
  check.eq("frontier retired at completion stamps nothing more", at_event.count, 1)
  check.eq("frontier retired at completion opens no socket", at_event.closed and at_event.closed["parent-retired"], nil)
  check.eq("frontier retired at completion finishes", at_event.state, "finished")
  check.eq("frontier queued sockets of a retired parent close", queued.closed and queued.closed["parent-retired"], 2)
  check.eq("frontier queued project stamps nothing more", queued.count, 1)
  local list = rig.instances_of(f.update)
  local a, b = list[1], list[2]
  check.eq("frontier update stamps the new version", b and b.version, 2)
  check.same("frontier update abuts the older copy", b and { b.footprint.left, b.footprint.top },
    a and { a.footprint.right, a.footprint.top })
  check.eq("frontier starved raises the event once", f.missing, 1)
  local u = project(f.ungenerated)
  check.truthy("frontier map wait ends when the chunk is generated",
    u.gate ~= "chunks" and (u.count == 1 or u.state == "finished"), check.show(u))
end

local function stalled_check()
  local f = storage.frontier
  local unsupplied, unreached = rig.call("get_instance", f.unsupplied) or {}, rig.call("get_instance", f.unreached) or {}
  check.same("frontier stalled for want of materials", { unsupplied.state, unsupplied.reason }, { "stalled", "missing-materials" })
  check.same("frontier stalled out of reach", { unreached.state, unreached.reason }, { "stalled", "no-network" })
end

case.checks = { [4200] = parked_check, [8400] = final_check, [11400] = stalled_check }

return case
