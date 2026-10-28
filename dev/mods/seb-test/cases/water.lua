-- water.lua: copies on water once the team can make landfill (D52), on a
-- force of its own that has researched it (regions 181-183).
--   plain:    a project toward water closes "water" at the shore and the
--             engine lays no landfill; a remote stamp on water is refused
--   covered:  superforced, a copy on water is stamped over the engine's
--             landfill ghosts
--   own:      a design that brings its own landfill grows over water without
--             superforce, and nothing else is laid
--   no-fill:  landfill = false still refuses water, superforced too
--   gate:     the materials gate waits for the engine's landfill like any
--             item; supplied, the copy is built on it
--   path:     paving on water: refused unless superforced; superforced it
--             goes on the engine's landfill and the copy completes
--   no-tech:  without the research (rig.FORCE), a superforced copy or paving
--             on water closes "water", not "building"
--   update:   a new version with a part on water is refused for a copy whose
--             project does not superforce, and built on landfill for one
--             whose project does
--   pump:     an offshore pump at the shore stands without landfill; one a
--             tile further out, whose own tile must be ground (a tile rule,
--             not its collision mask), is refused "water"

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "water" }

local PLAIN, GATE, PATH = 181, 182, 183
local FORCE = "seb-water"
local D = defines.direction

local function rect(name, x0, y0, x1, y1)
  local list = {}
  for x = x0, x1 - 1 do
    for y = y0, y1 - 1 do list[#list + 1] = { name = name, position = { x = x, y = y } } end
  end
  return list
end

local CELL = { rig.panel(1.5, 1.5) }
local PATH_PARTS = { { name = "iron-chest", position = { x = 0.5, y = 0.5 } } }
local PAVING = rect("stone-path", 0, 0, 2, 2)

local function design(force, entities, label, tiles)
  return rig.call("register_design", force, rig.blueprint(entities, { label = label, tiles = tiles }))
end

local function area(box)
  return { { box.left, box.top }, { box.right, box.bottom } }
end

local function tile_ghosts(surface, box)
  local counts = {}
  for _, g in pairs(surface.find_entities_filtered { area = area(box), type = "tile-ghost" }) do
    counts[g.ghost_name] = (counts[g.ghost_name] or 0) + 1
  end
  return counts
end

local function site(surface, region, wet, stock)
  local o = rig.region(region)
  rig.floor(surface, rig.box(o, -60, -60, 60, 60))
  for _, box in ipairs(wet) do rig.water(surface, rig.box(o, box[1], box[2], box[3], box[4])) end
  return o, rig.network(surface, rig.offset(o, -25, -25), stock, FORCE)
end

-- A remote stamp on water by the researched force: refused, nothing laid.
local function refused_stamp(surface, id, at, label)
  local copy, reason, where = rig.call("stamp", { force = FORCE, surface = surface, design = id, position = at, charted_only = false })
  check.same("water " .. label .. " remote stamp refused", { copy, reason, type(where) }, { nil, "water", "table" })
  local around = { left = at.x - 4, top = at.y - 4, right = at.x + 4, bottom = at.y + 4 }
  check.same("water " .. label .. " remote stamp lays nothing", { rig.ghosts(surface, around), tile_ghosts(surface, around) }, { 0, {} })
end

-- Offshore pumps facing the water east of x = 12: the one on the last land
-- tile stands as it is; the next one would need landfill under itself.
local function shore_pumps(surface, id, o)
  local function stamp(x)
    return rig.call("stamp", { force = FORCE, surface = surface, design = id, position = rig.offset(o, x, -20.5),
      direction = D.east, charted_only = false })
  end
  local on_shore = stamp(11.5)
  local copy, reason = stamp(12.5)
  local around = rig.box(o, 8, -24, 18, -17)
  check.truthy("water pump at the shore stamped", on_shore)
  check.same("water pump at the shore lays no landfill", tile_ghosts(surface, around), {})
  check.same("water pump with its own tile on water refused", { copy, reason }, { nil, "water" })
end

function case.setup(surface)
  rig.own_force(FORCE)
  game.forces[FORCE].technologies["landfill"].researched = true
  -- Region PLAIN: water east of x = 12 and in the south-west corner.
  local o = site(surface, PLAIN, { { 12, -60, 60, 60 }, { -60, 30, 0, 60 } }, { { "solar-panel", 50 } })
  local _, gate_chest = site(surface, GATE, { { -5, -5, 25, 25 } }, { { "solar-panel", 10 } })
  site(surface, PATH, { { -5, -5, 25, 25 } }, { { "landfill", 20 }, { "stone-brick", 20 }, { "iron-chest", 5 } })
  local s = {
    gate_chest = gate_chest,
    cell = design(FORCE, CELL, "Water cell"), pier = design(FORCE, CELL, "Water pier", rect("landfill", 0, 0, 3, 3)),
    path = design(FORCE, PATH_PARTS, "Water path", PAVING),
    plain_shore = design(FORCE, CELL, "Water shore plain"), forced_shore = design(FORCE, CELL, "Water shore forced"),
    bare_cell = rig.design(CELL, "Water bare cell"), bare_path = rig.design(PATH_PARTS, "Water bare path", { tiles = PAVING }),
  }
  storage.water = s
  refused_stamp(surface, s.cell, rig.offset(o, 30.5, 0.5), "panel")
  refused_stamp(surface, s.path, rig.offset(rig.region(PATH), 15, 15), "paving")
  shore_pumps(surface, design(FORCE, { { name = "offshore-pump", position = { x = 0.5, y = 0.5 } } }, "Water pump"), o)
end

local function start(key, force, id, at, extra)
  local params = { force = force, surface = game.surfaces.nauvis, design = id, point = at, charted_only = false,
    max_instances = 1, materials = false }
  for k, v in pairs(extra or {}) do params[k] = v end
  local project, reason = rig.call("start_project", params)
  check.truthy("water " .. key .. " project starts", project, reason)
  storage.water[key] = project
end

function case.start()
  local s, o = storage.water, rig.region(PLAIN)
  start("plain", FORCE, s.cell, rig.offset(o, 0.5, 0.5), {
    directions = { D.east }, max_instances = 8, open_early = true, max_building = 8 })
  start("covered", FORCE, s.cell, rig.offset(o, 46.5, 46.5), { superforce = true })
  start("own", FORCE, s.pier, rig.offset(o, 46.5, -46.5), { directions = { D.east }, max_instances = 2, open_early = true })
  start("no_fill", FORCE, s.pier, rig.offset(o, 46.5, 20.5), { landfill = false, superforce = true })
  start("no_tech", rig.FORCE, s.bare_cell, rig.offset(o, -40.5, 45.5), { superforce = true })
  start("no_tech_path", rig.FORCE, s.bare_path, rig.offset(o, -20, 45), { superforce = true })
  start("shore_plain", FORCE, s.plain_shore, rig.offset(o, 9.5, 10.5))
  start("shore_forced", FORCE, s.forced_shore, rig.offset(o, 9.5, 20.5), { superforce = true })
  start("gate", FORCE, s.cell, rig.offset(rig.region(GATE), 5.5, 5.5), { superforce = true, materials = true })
  start("paved", FORCE, s.path, rig.offset(rig.region(PATH), 6, 6), { superforce = true, materials = true })
end

local function copy_of(project)
  return rig.instances_of(project)[1]
end

local function closed_at_water(label, project)
  local p = rig.call("get_project", project) or {}
  local none = p.nothing_built or {}
  check.same("water " .. label .. " closes at water", { p.count, p.closed and p.closed.water, none.reason }, { 0, 1, "water" })
end

local function plain_row(surface)
  local s, o = storage.water, rig.region(PLAIN)
  local p = rig.call("get_project", s.plain) or {}
  check.same("water plain grows to the shore and closes there", { p.count, p.closed and p.closed.water }, { 4, 1 })
  local wet = rig.box(o, 12, -5, 40, 5)
  check.same("water plain lays no landfill on the water", tile_ghosts(surface, wet), {})
  check.eq("water plain puts no panel on the water", rig.ghosts(surface, wet) + rig.count(surface, wet, "solar-panel"), 0)
end

local function covered(surface)
  local copy = copy_of(storage.water.covered)
  check.truthy("water covered superforced copy stamped on water", copy)
  if not copy then return end
  check.same("water covered landfill ghosts under the copy", tile_ghosts(surface, copy.footprint), { landfill = 9 })
  check.same("water covered panel ghost and ghosts left", { rig.ghosts(surface, copy.footprint), copy.ghosts_left }, { 1, 10 })
end

local function own_landfill(surface)
  local s = storage.water
  local p = rig.call("get_project", s.own) or {}
  check.eq("water own landfill grows over water without superforce", p.count, 2)
  local copies, laid = rig.instances_of(s.own), {}
  for _, copy in ipairs(copies) do
    for name, n in pairs(tile_ghosts(surface, copy.footprint)) do laid[name] = (laid[name] or 0) + n end
  end
  check.same("water own landfill lays only the design's tiles", laid, { landfill = 18 })
end

local function waiting_gate()
  local s = storage.water
  local p = rig.call("get_project", s.gate) or {}
  local item = p.status and p.status.item or {}
  check.same("water gate waits for the engine's landfill", { p.count, p.gate, item.name, item.count }, { 0, "missing-materials", "landfill", 9 })
  s.gate_chest.insert { name = "landfill", count = 9 }
end

-- Updates: a second panel at the shore, on water.
local function update_shore(surface)
  local s, o = storage.water, rig.region(PLAIN)
  local two = { rig.panel(1.5, 1.5), rig.panel(4.5, 1.5) }
  design(FORCE, two, "Water shore plain")
  design(FORCE, two, "Water shore forced")
  local plain, forced = copy_of(s.shore_plain), copy_of(s.shore_forced)
  local ok, why = rig.call("update_instance", plain and plain.id or 0)
  check.same("water update refused on water for a plain project", { ok, why }, { false, "water" })
  ok, why = rig.call("update_instance", forced and forced.id or 0)
  check.eq("water update built on landfill for a superforced project", ok, true, why)
  local fp = forced and rig.call("get_instance", forced.id).footprint
  check.same("water update lays landfill under the new part", fp and tile_ghosts(surface, fp), { landfill = 6 })
end

local function settled(surface)
  local s = storage.water
  local gate = copy_of(s.gate)
  check.eq("water gate copy built on landfill", gate and gate.state, "complete")
  if gate then check.eq("water gate landfill laid", surface.count_tiles_filtered { area = area(gate.footprint), name = "landfill" }, 9) end
  local paved = copy_of(s.paved)
  check.eq("water path copy completes", paved and paved.state, "complete")
  if not paved then return end
  local tiles = surface.find_tiles_filtered { area = area(paved.footprint), name = "stone-path" }
  local on_landfill = 0
  for _, tile in ipairs(tiles) do
    if tile.hidden_tile == "landfill" then on_landfill = on_landfill + 1 end
  end
  check.same("water path paving laid on landfill", { #tiles, on_landfill }, { 4, 4 })
end

local function verify(surface)
  plain_row(surface)
  covered(surface)
  own_landfill(surface)
  local s = storage.water
  closed_at_water("no-fill", s.no_fill)
  closed_at_water("no-tech copy", s.no_tech)
  closed_at_water("no-tech paving", s.no_tech_path)
  waiting_gate()
  update_shore(surface)
end

case.checks = { [600] = verify, [3000] = settled }

return case
