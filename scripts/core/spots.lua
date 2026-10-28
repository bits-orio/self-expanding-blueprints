-- A spot that passed the rules (growth.lua), on the map: the terrain, the
-- design's probes, the world around and under it, the materials gate, then
-- the stamp, or in a plan the planned copy. Each stage adds what it looked
-- at to the spot's record of its work (spot.work, work.lua), so the spot
-- pays for what it did however far it got.

local const = require("scripts.const")
local geometry = require("scripts.core.geometry")
local checks = require("scripts.core.checks")
local gates = require("scripts.core.gates")
local stamp = require("scripts.core.stamp")
local probes = require("scripts.core.probes")
local previews = require("scripts.core.previews")
local work = require("scripts.core.work")

local spots = {}

local REASON = const.REASON

function spots.closed(reason, position)
  return { kind = "closed", reason = reason, position = position }
end

local function gate(reason, item)
  return { kind = "gate", reason = reason, item = item }
end

-- The chunks under a footprint, which a check walks one by one.
function spots.chunks(footprint)
  local n = 0
  geometry.each_chunk(footprint, function() n = n + 1 end)
  return n
end

-- A dry run plans regardless of materials and robots. A project's first
-- copy goes down even where no robots reach yet, as a pasted blueprint
-- would: its ghosts wait for robots or the player's own hands. Later copies
-- wait for robots, so growth never spreads ghosts over land nobody builds.
-- A single remote stamp (no project id) still refuses, as documented.
local function materials_gate(project, surface, force, spot, socket)
  if not project.gates.materials or project.dry_run then return nil end
  local cost = gates.cost_of(spot)
  spot.work.checked = spot.work.checked + #cost
  local ok, why, item = gates.materials(surface, force, geometry.box_center(spot.footprint),
    cost, project.gates.reserve)
  local first_copy = socket.kind == "seed" and project.id ~= nil
  if ok or (why == REASON.no_network and first_copy) then return nil end
  return gate(why, item)
end

-- Enemy buildings near the spot, and water a project told to bring no
-- landfill over.
local function check_surroundings(project, surface, footprint)
  local rules = project.rules
  local d = rules.enemy_distance
  if d and d > 0 then
    local around = { { footprint.left - d, footprint.top - d }, { footprint.right + d, footprint.bottom + d } }
    if surface.count_entities_filtered { area = around, force = "enemy", type = { "unit-spawner", "turret" }, limit = 1 } > 0 then
      return spots.closed(REASON.enemies)
    end
  end
  if rules.no_landfill
    and surface.count_tiles_filtered { area = geometry.area(footprint), collision_mask = "water_tile", limit = 1 } > 0 then
    return spots.closed(REASON.water)
  end
end

-- What the obstacle check did (checks.obstacles): it looked at the parts
-- and Keep clear tiles, what stood in their way, and water.
local function charge_check(spot)
  local record = spot.work
  record.checked = record.checked + work.check_size(spot.prepared) + spot.water_looks
  record.in_way, record.water = record.in_way + spot.in_way, record.water + spot.water_tiles
end

-- A socket that already passed the pre-check and is parked on the materials
-- gate re-tests that (cheap) gate first, so a retry costs microseconds; the
-- pre-check runs again once the gate lets it through, right before the
-- stamp, and so does the gate when the pre-check found more for the stamp
-- to take (explosives for cliffs, landfill for water): those are not in the
-- first test.
local function check_world(project, surface, force, spot, socket)
  local nearby = check_surroundings(project, surface, spot.footprint)
  if nearby then return nearby end
  if socket.waiting then
    local held = materials_gate(project, surface, force, spot, socket)
    if held then return held end
  end
  local reason, where = checks.obstacles(surface, force, spot)
  charge_check(spot)
  if reason then return spots.closed(reason, where) end
  if socket.waiting and not gates.adds_cost(spot) then return nil end
  local held = materials_gate(project, surface, force, spot, socket)
  if held then socket.waiting = true end
  return held
end

-- The stamp did its work (and undid it, if it came out short) either way.
local function stamp_spot(project, surface, force, spot, socket)
  spot.work.stamps = spot.work.stamps + 1
  spot.work.built = spot.work.built + work.check_size(spot.prepared)
  spot.work.poles = (spot.work.poles or 0) + work.poles(spot.prepared)
  local instance, reason = stamp.run(spot, {
    surface = surface, force = force, project_id = project.id, parent = socket.from, socket = socket.index,
  })
  if not instance then return spots.closed(reason or REASON.stamp_short, socket.position) end
  return { kind = "stamped", instance = instance, spot = spot }
end

-- A verdict of growth.try's kinds.
function spots.on_map(project, socket, spot)
  -- Another plan's look-only ghosts never stand in a copy's way.
  spot.work.checked = spot.work.checked + previews.make_room(project.surface_index, spot.footprint, project.id)
  local surface, force = game.surfaces[project.surface_index], game.forces[project.force_index]
  -- The map first: a probe over a chunk not yet generated would find no ore.
  spot.work.chunks = spot.work.chunks + spots.chunks(spot.footprint)
  local terrain = checks.terrain(surface, force, spot.footprint, project.rules)
  if terrain then return terrain end
  local failed, where, looked = probes.check(surface, spot)
  spot.work.probes = spot.work.probes + looked
  if failed then return spots.closed(failed, where) end
  local verdict = check_world(project, surface, force, spot, socket)
  if verdict then return verdict end
  if project.dry_run then return { kind = "planned", spot = spot } end
  return stamp_spot(project, surface, force, spot, socket)
end

return spots
