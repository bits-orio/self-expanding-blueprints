-- regressions.lua: cases from the second review of the fixes.
--   plain:     a drawn socket that names a plain design stamps one end piece and the project finishes
--   abs:       implicit growth of absolutely snapped designs steps one grid cell, however the content sits
--              inside its cell and whichever way the copy faces
--   drag:      a drag fill of a design centred on its origin never seeds a copy that pokes out of the rectangle
--   foreign:   a same-name entity of the player's inside the footprint is not adopted as the instance's
--   far:       coordinates beyond the map are refused at the boundary

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "regressions" }
local D = defines.direction

-- Regions in one column, a row (400 tiles) apart: the cell strips below are wider than a region.
local ABS_REGION, DRAG_REGION, PLAIN_REGION, FOREIGN_REGION = 72, 76, 80, 84
local GRID, REL = { x = 5, y = 4 }, { x = 1, y = 2 }
local STEP = { [D.east] = { 1, 0 }, [D.south] = { 0, 1 }, [D.west] = { -1, 0 }, [D.north] = { 0, -1 } }
local PITCH = 70

local function start(design, extra)
  local params = { force = rig.FORCE, surface = game.surfaces.nauvis, design = design, charted_only = false, materials = false }
  for k, v in pairs(extra) do params[k] = v end
  local id, reason = rig.call("start_project", params)
  check.truthy("regress start design " .. design, id, reason)
  return id
end

local function footprints(project)
  local list = {}
  for i, inst in ipairs(rig.instances_of(project)) do list[i] = inst.footprint end
  return list
end

-- A site with a floor and a network at each of `count` cells, PITCH apart;
-- (dx, dy) places each network relative to its cell's origin.
local function cells(surface, region, count, dx, dy)
  local o = rig.region(region)
  rig.floor(surface, rig.box(o, -PITCH, -PITCH, count * PITCH, 2 * PITCH))
  for i = 0, count - 1 do rig.network(surface, rig.offset(o, i * PITCH + dx, dy)) end
  return o
end

function case.setup(surface)
  local f = { abs = {}, drags = {} }
  storage.regress = f
  -- plain end pieces
  rig.site(surface, PLAIN_REGION)
  f.seed = rig.design({ rig.panel(1.5, 1.5), rig.socket(3.5, 1.5, D.east, "R2 end") }, "R2 seed")
  f.end_piece = rig.design({ { name = "accumulator", position = { x = 1, y = 1 } }, rig.entry(0.5, 0.5, D.east) }, "R2 end")
  -- absolutely snapped designs: content at (1,1) inside its cell, and at the origin
  local o = cells(surface, ABS_REGION, 6, 5, 5)
  f.plus = rig.call("register_design", rig.FORCE,
    rig.blueprint({ rig.panel(2.5, 2.5) }, { label = "R2 plus", grid = GRID, absolute = REL }))
  f.origin = rig.call("register_design", rig.FORCE,
    rig.blueprint({ rig.panel(1.5, 1.5) }, { label = "R2 origin", grid = GRID, absolute = REL }))
  f.abs_origin = o
  -- a design centred on its origin: four panels, grid 8x8
  -- The drags run over [-20, 20] of their cell: the network stands clear of it.
  local d = cells(surface, DRAG_REGION, 8, -24, -24)
  f.centred = rig.call("register_design", rig.FORCE, rig.blueprint(
    { rig.panel(-1.5, -1.5), rig.panel(1.5, -1.5), rig.panel(-1.5, 1.5), rig.panel(1.5, 1.5) },
    { label = "R2 centred", grid = { x = 8, y = 8 }, absolute = { x = 0, y = 0 } }))
  f.drag_origin = d
  -- a foreign chest in a footprint's gap
  local a = rig.region(FOREIGN_REGION)
  rig.floor(surface, rig.box(a, -20, -20, 40, 40))
  f.pair = rig.design({ { name = "iron-chest", position = { x = 0.5, y = 0.5 } },
    { name = "iron-chest", position = { x = 4.5, y = 0.5 } } }, "R2 pair")
  local id, why = rig.call("stamp", { force = rig.FORCE, surface = surface, design = f.pair, build_position = a })
  check.truthy("regress pair stamped", id, why)
  f.pair_id = id
  if id then
    local fp = rig.call("get_instance", id).footprint
    f.foreign = surface.create_entity { name = "iron-chest", position = { fp.left + 2.5, fp.top + 0.5 }, force = rig.FORCE }
    local ghosts = surface.find_entities_filtered { area = { { fp.left, fp.top }, { fp.right, fp.bottom } }, type = "entity-ghost" }
    table.sort(ghosts, function(x, y) return x.position.x < y.position.x end)
    ghosts[1].revive { raise_revive = true }
    ghosts[2].destroy()
  end
  -- far away: refused before anything is stored
  for _, pos in ipairs({ { 1e12, 0.5 }, { 1e7, 0.5 }, { -3e6, 0 } }) do
    local project, reason = rig.call("start_project", { force = rig.FORCE, surface = surface, design = f.seed, position = pos })
    if project then rig.call("stop_project", project) end
    check.same("regress far position " .. pos[1] .. " refused", { project, reason }, { nil, "invalid-position" })
  end
  local project, reason = rig.call("start_project", { force = rig.FORCE, surface = surface, design = f.seed,
    area = { left = -5, top = 0, right = 1e9, bottom = 10 } })
  if project then rig.call("stop_project", project) end
  check.same("regress far area refused", { project, reason }, { nil, "invalid-area" })
end

function case.start()
  local f = storage.regress
  f.plain = start(f.seed, { build_position = rig.region(PLAIN_REGION) })
  -- content at (1,1): grow each way, facing north
  local o = f.abs_origin
  for i, grow in ipairs({ D.east, D.south, D.west, D.north }) do
    f.abs[#f.abs + 1] = { design = f.plus, facing = D.north, grow = grow, project = start(f.plus, {
      point = rig.offset(o, (i - 1) * PITCH + 20.5, 20.5), direction = D.north, directions = { grow }, max_instances = 3 }) }
  end
  -- content at the origin: facing east and south, growing east and south
  for i, facing in ipairs({ D.east, D.south }) do
    for j, grow in ipairs({ D.east, D.south }) do
      f.abs[#f.abs + 1] = { design = f.origin, facing = facing, grow = grow, project = start(f.origin, {
        point = rig.offset(o, (4 + i - 1) * PITCH + 20.5, (j - 1) * 25 + 20.5), direction = facing, directions = { grow }, max_instances = 3 }) }
    end
  end
  -- drag fills at eight alignments against the 8x8 grid
  for ax = 0, 7 do
    local origin = f.drag_origin
    local area = rig.box(origin, ax * PITCH - 20 + ax, -20, ax * PITCH + 20 + ax, 20)
    f.drags[ax + 1] = { area = area, project = start(f.centred, { area = area }) }
  end
end

local function turned(facing)
  if facing == D.east or facing == D.west then return { x = GRID.y, y = GRID.x } end
  return { x = GRID.x, y = GRID.y }
end

local function check_abs(f)
  local names = { [D.north] = "N", [D.east] = "E", [D.south] = "S", [D.west] = "W" }
  for _, a in ipairs(f.abs) do
    local list = footprints(a.project)
    local label = "regress abs facing " .. names[a.facing] .. " grows " .. names[a.grow]
    check.eq(label .. " count", #list, 3)
    local g, s = turned(a.facing), STEP[a.grow]
    local want = { s[1] * ((a.grow == D.east or a.grow == D.west) and g.x or g.y),
      s[2] * ((a.grow == D.east or a.grow == D.west) and g.x or g.y) }
    for i = 2, #list do
      check.same(label .. " step " .. i, { list[i].left - list[i - 1].left, list[i].top - list[i - 1].top }, want)
    end
  end
end

-- Lattice lines c = 8n whose 6-wide footprint [c - 3, c + 3) lies inside [low, high).
local function fits(low, high)
  local n = 0
  for c = math.ceil((low + 3) / 8) * 8, high - 3, 8 do n = n + 1 end
  return n
end

local function check_drags(f)
  for ax, drag in ipairs(f.drags) do
    local list, area = footprints(drag.project), drag.area
    local inside = 0
    for _, fp in ipairs(list) do if fp.left >= area.left and fp.top >= area.top and fp.right <= area.right and fp.bottom <= area.bottom then inside = inside + 1 end end
    local label = "regress drag alignment " .. (ax - 1)
    check.eq(label .. " finished", (rig.call("get_project", drag.project) or {}).state, "finished")
    check.eq(label .. " every copy inside the rectangle", inside, #list)
    check.eq(label .. " fills every grid position that fits", #list, fits(area.left, area.right) * fits(area.top, area.bottom))
  end
end

local function verify()
  local f = storage.regress
  local p = rig.call("get_project", f.plain) or {}
  check.same("regress end piece: seed and one end piece, then finished", { p.count, p.state }, { 2, "finished" })
  check_abs(f)
  check_drags(f)
  local inst = rig.call("get_instance", f.pair_id) or {}
  check.same("regress foreign chest is not adopted", { inst.state, inst.entity_count }, { "incomplete", 1 })
  rig.call("remove_instance", f.pair_id)
  check.eq("regress foreign chest survives the retire", f.foreign and f.foreign.valid and f.foreign.to_be_deconstructed(), false)
end

case.checks = { [5400] = verify }

return case
