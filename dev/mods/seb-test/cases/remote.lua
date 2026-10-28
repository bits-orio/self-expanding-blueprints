-- remote.lua: the remote interface checks its arguments at the boundary.
--   refusals:  bad values return nil and "invalid-<field>" and store nothing
--   forms:     positions as {x, y}, areas in all three engine forms
--   lattice:   a rail design refuses a build_position off its 2x2 grid
--   position:  start_project's position lands the entry arrow on that tile,
--              exactly as stamp's does

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "remote" }

local REGION = 12
local D = defines.direction

local WITH_ENTRY = {
  { name = "assembling-machine-1", position = { x = 1.5, y = 1.5 } },
  { name = "small-electric-pole", position = { x = 4.5, y = 0.5 } },
  { name = "seb-entry", position = { x = 0.5, y = 1.5 }, direction = D.east },
}
local RAIL = { { name = "straight-rail", position = { x = 1, y = 1 } } }

local function refused(label, fn, params, want)
  local id, reason = rig.call(fn, params)
  check.eq("remote " .. label .. " refused", id, nil)
  check.eq("remote " .. label .. " reason", reason, want)
end

-- Params for `design` in this case's region, with `extra` merged in.
local function params_for(design, extra)
  local params = { force = rig.FORCE, surface = game.surfaces.nauvis, design = design, charted_only = false }
  for k, v in pairs(extra) do params[k] = v end
  return params
end

local function refusals(r, o)
  local at = rig.offset(o, 10.5, 10.5)
  refused("stamp without position", "stamp", params_for(r.entry, {}), "invalid-position")
  refused("stamp with two positions", "stamp", params_for(r.entry, { position = at, build_position = at }), "invalid-position")
  refused("stamp diagonal", "stamp", params_for(r.entry, { position = at, direction = D.northeast }), "invalid-direction")
  refused("stamp text position", "stamp", params_for(r.entry, { position = "here" }), "invalid-position")
  refused("stamp non-table params", "stamp", 42, "invalid-params")
  refused("project zero count", "start_project", params_for(r.entry, { position = at, max_instances = 0 }), "invalid-max_instances")
  refused("project diagonal list", "start_project", params_for(r.entry, { position = at, directions = { D.east, 3 } }), "invalid-directions")
  refused("project negative reserve", "start_project", params_for(r.entry, { position = at, reserve = -1 }), "invalid-reserve")
  refused("project text materials", "start_project", params_for(r.entry, { position = at, materials = "yes" }), "invalid-materials")
  refused("project empty area", "start_project", params_for(r.entry, { area = rig.box(o, 0, 0, 0, 5) }), "invalid-area")
  refused("project point and area", "start_project", params_for(r.entry, { point = at, area = rig.box(o, 0, 0, 9, 9) }), "invalid-position")
  refused("stamp boolean force", "stamp", params_for(r.entry, { force = true, position = at }), "unknown-force")
  refused("stamp refused force index", "stamp", params_for(r.entry, { force = -1, position = at }), "unknown-force")
  refused("stamp force given as surface", "stamp", params_for(r.entry, { surface = game.forces.player, position = at }), "unknown-surface")
  refused("project point off the map", "start_project", params_for(r.entry, { point = { 1e8, 0 } }), "invalid-point")
  refused("stamp build position off the map", "stamp", params_for(r.entry, { build_position = { 0, -3e6 } }), "invalid-build_position")
  local id, reason = rig.call("register_design", rig.FORCE, rig.blueprint(WITH_ENTRY), 5)
  check.eq("remote numeric name refused", id, nil)
  check.eq("remote numeric name reason", reason, "invalid-name")
end

local function lattice(r, o)
  local off = rig.offset(o, 61, 10)
  refused("rail stamp off-grid", "stamp", params_for(r.rail, { build_position = off }), "off-grid")
  refused("rail project off-grid", "start_project", params_for(r.rail, { build_position = off }), "off-grid")
  local id, reason = rig.call("stamp", params_for(r.rail, { build_position = rig.offset(o, 62, 10) }))
  check.truthy("remote rail stamp on-grid", id, reason)
end

function case.setup(surface)
  local o = rig.region(REGION)
  rig.floor(surface, rig.box(o, -10, -10, 130, 130))
  local r = { entry = rig.design(WITH_ENTRY, "Remote entry"), rail = rig.design(RAIL, "Remote rail") }
  storage.remote = r
  refusals(r, o)
  lattice(r, o)
  local array_at = { o.x + 10.5, o.y + 10.5 }
  local id, reason = rig.call("stamp", params_for(r.entry, { position = array_at }))
  check.truthy("remote array position stamped", id, reason)
  local first
  first, reason = rig.call("stamp", params_for(r.entry, { position = rig.offset(o, 30.5, 10.5) }))
  check.truthy("remote reference stamp", first, reason)
  r.reference = first and rig.call("get_instance", first).footprint
end

local function start(design, extra)
  local id, reason = rig.call("start_project", params_for(design, extra))
  check.truthy("remote project starts", id, reason)
  return id
end

function case.start()
  local r, o = storage.remote, rig.region(REGION)
  r.tile_centre = start(r.entry, { position = rig.offset(o, 30.5, 30.5), max_instances = 1, materials = false })
  r.tile_corner = start(r.entry, { position = rig.offset(o, 30, 50), max_instances = 1, materials = false })
  r.corners = start(r.entry, { area = { left_top = rig.offset(o, 70, 70), right_bottom = rig.offset(o, 90, 90) },
    max_instances = 1, materials = false })
  local lt, rb = rig.offset(o, 100, 70), rig.offset(o, 120, 90)
  r.pairs = start(r.entry, { area = { { lt.x, lt.y }, { rb.x, rb.y } }, max_instances = 1, materials = false })
end

local function shifted(box, dy)
  return box and { left = box.left, top = box.top + dy, right = box.right, bottom = box.bottom + dy }
end

-- The AI Agent Bridge probe and its read tools.
local function agent_tools()
  local manifest = rig.call("agent_tools_v1")
  check.eq("remote agent manifest version", manifest and manifest.v, 1)
  check.truthy("remote agent manifest lists projects", manifest and manifest.tools.seb_projects)
  local list = rig.call("seb_projects", { force = rig.FORCE })
  check.truthy("remote agent projects listed", list and #list.projects > 0)
  local one = list and list.projects[1] and rig.call("seb_project", { force = rig.FORCE, id = list.projects[1].id })
  check.truthy("remote agent project detail has a status", one and one.status and one.status.level)
  local designs = rig.call("seb_designs", { force = rig.FORCE })
  check.truthy("remote agent designs listed", designs and #designs.designs > 0)
end

local function state_of(id)
  local project = rig.call("get_project", id)
  return project and project.state
end

-- The write tools, which seb-test's settings stage turns on.
local function agent_write_tools()
  local manifest = rig.call("agent_tools_v1")
  check.truthy("remote agent write tools listed when allowed", manifest and manifest.tools.seb_grow and manifest.tools.seb_stop_project)
  local at = rig.offset(rig.region(REGION), 20.5, 110.5)
  local grown = rig.call("seb_grow", { force = rig.FORCE, design = storage.remote.entry, x = at.x, y = at.y, count = 1, sides = "east" })
  check.eq("remote agent grow starts a project", grown and grown.ok, true, grown and grown.reason)
  local id = grown and grown.project
  check.eq("remote agent pause", rig.call("seb_pause_project", { force = rig.FORCE, id = id }).ok, true)
  check.eq("remote agent paused it", state_of(id), "paused")
  check.eq("remote agent resume", rig.call("seb_resume_project", { force = rig.FORCE, id = id }).ok, true)
  check.eq("remote agent stop", rig.call("seb_stop_project", { force = rig.FORCE, id = id }).ok, true)
  check.eq("remote agent stopped it", state_of(id), "stopped")
  local ok, message = pcall(rig.call, "seb_pause_project", { force = rig.FORCE, id = id })
  check.truthy("remote agent refuses a stopped project", not ok and tostring(message):find("no such project"), message)
  ok, message = pcall(rig.call, "seb_pause_project", { force = "enemy", id = storage.remote.tile_centre })
  check.truthy("remote agent refuses another team's project", not ok and tostring(message):find("no such project"), message)
  ok, message = pcall(rig.call, "seb_grow", { force = rig.FORCE, design = storage.remote.entry, x = at.x, y = at.y, sides = "up" })
  check.truthy("remote agent refuses an unknown side", not ok and tostring(message):find("no side"), message)
end

-- The remote clear orders deconstruction in an area.
local function remote_clear(surface)
  local o = rig.region(REGION)
  local chest = surface.create_entity { name = "iron-chest", position = rig.offset(o, 100.5, 100.5), force = rig.FORCE }
  local n = rig.call("clear", { force = rig.FORCE, surface = surface, area = rig.box(o, 99, 99, 103, 103) })
  check.eq("remote clear orders the chest", n, 1)
  check.truthy("remote clear marked it", chest.to_be_deconstructed())
end

-- A blueprint or book handed over as itself, not as a string.
local function objects()
  local inventory = game.create_inventory(3)
  inventory[1].set_stack { name = "blueprint" }
  inventory[1].set_blueprint_entities({ { entity_number = 1, name = "small-lamp", position = { x = 0.5, y = 0.5 } } })
  local id, created = rig.call("register_design", rig.FORCE, inventory[1], "Remote object")
  check.truthy("remote register takes a blueprint stack", id and created, id)
  inventory[2].set_stack { name = "blueprint-book" }
  local inner = inventory[2].get_inventory(defines.inventory.item_main)
  inner.insert { name = "blueprint" }
  inner[1].set_blueprint_entities({ { entity_number = 1, name = "small-lamp", position = { x = 0.5, y = 0.5 } } })
  inner[1].label = "Remote book page"
  local ids = rig.call("register_design", rig.FORCE, inventory[2])
  check.truthy("remote register takes a book stack", type(ids) == "table" and #ids == 1, ids)
  local _, reason = rig.call("register_design", rig.FORCE, inventory[3])
  check.eq("remote register refuses an empty stack", reason, "invalid-design")
  inventory.destroy()
  local named
  for _, row in ipairs(rig.call("list_designs", rig.FORCE)) do
    if row.id == id then named = row.name end
  end
  check.eq("remote register from a stack uses the given name", named, "Remote object")
end

local function verify(surface)
  objects()
  agent_tools()
  agent_write_tools()
  remote_clear(surface)
  local r = storage.remote
  local centre, corner = rig.instances_of(r.tile_centre)[1], rig.instances_of(r.tile_corner)[1]
  check.same("remote project position lands like stamp", centre and centre.footprint, shifted(r.reference, 20))
  check.same("remote position names the tile", corner and corner.footprint, shifted(r.reference, 40))
  check.eq("remote corner-form area stamps", #rig.instances_of(r.corners), 1)
  check.eq("remote pair-form area stamps", #rig.instances_of(r.pairs), 1)
end

case.checks = { [600] = verify }

return case
