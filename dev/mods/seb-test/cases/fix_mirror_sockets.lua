-- fix_mirror_sockets.lua: a flipped paste of a design that grows through its
-- own socket (regions 177-178). An arm of chests with an inserter under it
-- and a socket on its east end grows three copies east as drawn; flipped,
-- the socket is on the west end and the same three copies grow west, the
-- whole growth the drawn one turned over.

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "fix_mirror_sockets" }

local DRAWN, FLIPPED = 177, 178
local D = defines.direction
local PARTS = { ["wooden-chest"] = true, ["inserter"] = true }

local function arm()
  return rig.blueprint({
    { name = "wooden-chest", position = { x = 0.5, y = 0.5 } }, { name = "wooden-chest", position = { x = 1.5, y = 0.5 } },
    { name = "wooden-chest", position = { x = 2.5, y = 0.5 } },
    { name = "inserter", position = { x = 1.5, y = 1.5 }, direction = D.east },
    rig.socket(3.5, 0.5, D.east),
  }, { label = "Mirror arm" })
end

local function start(surface, region, mirrored)
  local id, reason = rig.call("start_project", {
    force = rig.FORCE, surface = surface, design = "Mirror arm", charted_only = false, max_instances = 3,
    point = rig.offset(rig.region(region), 0, 0), mirrored = mirrored, materials = false,
    -- Sockets open as copies are placed: the site's robots have no chests.
    open_early = true, max_building = 8,
  })
  check.truthy("fix_mirror_sockets project starts in region " .. region, id, reason)
end

-- The parts near a region's origin, built or ghosts, as sorted lines relative
-- to their top-left (turned over when `flip`), and their leftmost x from the
-- origin.
local function growth(surface, region, flip)
  local o = rig.region(region)
  local list = {}
  for _, e in pairs(surface.find_entities_filtered { area = { { o.x - 30, o.y - 10 }, { o.x + 30, o.y + 10 } }, force = rig.FORCE }) do
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
  return lines, minx - o.x, maxx - o.x
end

function case.setup(surface)
  for _, region in ipairs({ DRAWN, FLIPPED }) do rig.site(surface, region) end
  rig.call("register_design", rig.FORCE, arm())
  start(surface, DRAWN, false)
  start(surface, FLIPPED, true)
end

local function grown()
  local surface = game.surfaces.nauvis
  local drawn, _, drawn_right = growth(surface, DRAWN, false)
  local flipped, flipped_left = growth(surface, FLIPPED, true)
  check.eq("fix_mirror_sockets three copies grow as drawn", #drawn, 12)
  check.truthy("fix_mirror_sockets as drawn they grow east", drawn_right > 6, check.show(drawn_right))
  check.truthy("fix_mirror_sockets flipped they grow west", flipped_left < -6, check.show(flipped_left))
  check.same("fix_mirror_sockets the flipped growth is the drawn one turned over", flipped, drawn)
end

case.checks = { [900] = grown }

return case
