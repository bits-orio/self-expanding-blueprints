-- fix_mirror.lua: a flipped paste grows the design's mirror image (regions
-- 174-176). A lopsided design grown as drawn and mirrored: the mirrored
-- copy's ghosts are the drawn copy's turned over, its inserter facing the
-- other way. The mirror twin stays out of the design list, follows the
-- design's next version, and a design with a rail cannot be mirrored.

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "fix_mirror" }

local DRAWN, MIRRORED, NEXT = 174, 175, 176
local D = defines.direction

-- An L of chests with an inserter in its corner, facing east.
local function lopsided(extra)
  local list = {
    { name = "wooden-chest", position = { x = 0.5, y = 0.5 } }, { name = "wooden-chest", position = { x = 1.5, y = 0.5 } },
    { name = "wooden-chest", position = { x = 2.5, y = 0.5 } }, { name = "wooden-chest", position = { x = 0.5, y = 1.5 } },
    { name = "inserter", position = { x = 2.5, y = 1.5 }, direction = D.east },
  }
  if extra then list[#list + 1] = { name = "wooden-chest", position = { x = 3.5, y = 0.5 } } end
  return rig.blueprint(list, { label = "Mirror L" })
end

local function start(surface, region, mirrored)
  local id, reason = rig.call("start_project", {
    force = rig.FORCE, surface = surface, design = "Mirror L", charted_only = false, max_instances = 1,
    point = rig.offset(rig.region(region), 0, 0), mirrored = mirrored, materials = false,
  })
  check.truthy("fix_mirror project starts in region " .. region, id, reason)
end

local PARTS = { ["wooden-chest"] = true, ["inserter"] = true }

-- The copy near a region's origin, built or still ghosts, as sorted
-- "name x y direction" lines relative to its top-left; turned over when `flip`.
local function copy(surface, region, flip)
  local o = rig.region(region)
  local list = {}
  for _, e in pairs(surface.find_entities_filtered { area = { { o.x - 10, o.y - 10 }, { o.x + 10, o.y + 10 } }, force = rig.FORCE }) do
    local name = e.type == "entity-ghost" and e.ghost_name or e.name
    if PARTS[name] then list[#list + 1] = { name = name, x = e.position.x, y = e.position.y, dir = e.direction } end
  end
  local minx, miny, maxx = math.huge, math.huge, -math.huge
  for _, p in ipairs(list) do minx, miny, maxx = math.min(minx, p.x), math.min(miny, p.y), math.max(maxx, p.x) end
  local lines = {}
  for _, p in ipairs(list) do
    local x, dir = p.x - minx, p.dir
    if flip then x, dir = maxx - p.x, (16 - dir) % 16 end
    lines[#lines + 1] = table.concat({ p.name, x, p.y - miny, dir }, " ")
  end
  table.sort(lines)
  return lines
end

function case.setup(surface)
  for _, region in ipairs({ DRAWN, MIRRORED, NEXT }) do rig.site(surface, region) end
  rig.call("register_design", rig.FORCE, lopsided())
  start(surface, DRAWN, false)
  local before = #rig.call("list_designs", rig.FORCE)
  start(surface, MIRRORED, true)
  check.eq("fix_mirror the mirror twin is not a design of the list", #rig.call("list_designs", rig.FORCE), before)
  local rail = rig.blueprint({ { name = "straight-rail", position = { x = 1, y = 1 } } }, { label = "Mirror rail" })
  rig.call("register_design", rig.FORCE, rail)
  local id, why = rig.call("start_project", {
    force = rig.FORCE, surface = surface, design = "Mirror rail", charted_only = false, max_instances = 1,
    point = rig.offset(rig.region(NEXT), 30, 30), mirrored = true,
  })
  check.same("fix_mirror a design with a rail cannot be mirrored", { id, why }, { nil, "cannot-mirror" })
end

local function mirrored_copy()
  local surface = game.surfaces.nauvis
  local drawn, mirrored = copy(surface, DRAWN, false), copy(surface, MIRRORED, true)
  check.eq("fix_mirror the drawn copy is stamped", #drawn, 5)
  check.same("fix_mirror the flipped copy is the drawn one turned over", mirrored, drawn)
  local again, why = rig.call("start_project", {
    force = rig.FORCE, surface = surface, design = "Mirror L", charted_only = false, max_instances = 1,
    point = rig.offset(rig.region(DRAWN), 0, 0), materials = false,
  })
  check.same("fix_mirror a project started on copies already there is refused", { again, why }, { nil, "seed-occupied" })
  rig.call("register_design", rig.FORCE, lopsided(true))
  start(surface, NEXT, true)
end

local function next_version()
  local surface = game.surfaces.nauvis
  check.eq("fix_mirror a flipped paste after a new version grows the new version", #copy(surface, NEXT, true), 6)
end

case.checks = { [240] = mirrored_copy, [600] = next_version }

return case
