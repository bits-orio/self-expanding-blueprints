-- plugs.lua: numbered plugs, and sides grown together with sockets.
--   plugs: a design with two plugs numbered 1 and 2; a socket numbered 2
--          attaches its child by plug 2 (turned to match), one numbered 1
--          by plug 1 (unturned), one numbered 3 closes as "no-plug"; a
--          design with two plugs without numbers is listed as invalid
--   sides: a chest with one socket east grows east only, unless its
--          project grows sides with its sockets: then south too

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "plugs" }

local PLUG_REGION, SIDES_REGION, OLD_REGION = 195, 196, 197
local D = defines.direction

local function numbered(entity, n)
  entity.control_behavior = { sections = { sections = { { index = 1, filters = {
    { index = 1, type = "virtual", name = "signal-" .. n, quality = "normal", comparator = "=", count = n },
  } } } } }
  return entity
end

local CHEST = { name = "iron-chest", position = { x = 0.5, y = 0.5 } }

local function hub(n, label)
  return (rig.design({ CHEST, numbered(rig.socket(1.5, 0.5, D.east, "Two plugs"), n) }, label))
end

function case.setup(surface)
  rig.site(surface, PLUG_REGION)
  rig.site(surface, SIDES_REGION)
  rig.site(surface, OLD_REGION)
  local id = rig.design({ CHEST, numbered(rig.entry(0.5, 0.5, D.east), 1), numbered(rig.entry(0.5, 0.5, D.south), 2) },
    "Two plugs")
  check.truthy("plugs two numbered plugs register", id)
  rig.design({ CHEST, rig.entry(0.5, 0.5, D.east), rig.entry(0.5, 0.5, D.south) }, "Two bare plugs")
  storage.plugs = {
    hubs = { hub(1, "Hub one"), hub(2, "Hub two"), hub(3, "Hub three") },
    side = rig.design({ CHEST, rig.socket(1.5, 0.5, D.east, "") }, "Side chest"),
  }
end

local function start(design, region, dy, extra)
  local o = rig.region(region)
  local params = {
    force = rig.FORCE, surface = game.surfaces.nauvis, design = design, charted_only = false,
    position = { x = o.x + 0.5, y = o.y + dy + 0.5 }, max_instances = 2,
  }
  for k, v in pairs(extra or {}) do params[k] = v end
  local id, reason = rig.call("start_project", params)
  check.truthy("plugs project starts", id, reason)
  return id
end

function case.start()
  local s = storage.plugs
  s.hub_projects = {}
  for i, design in ipairs(s.hubs) do s.hub_projects[i] = start(design, PLUG_REGION, (i - 1) * 8) end
  s.sides = start(s.side, SIDES_REGION, 0, { max_instances = 3, directions = { D.south }, sides_with_sockets = true })
  s.old = start(s.side, OLD_REGION, 0, { max_instances = 3, directions = { D.south } })
end

local function child_of(project_id)
  for _, inst in ipairs(rig.instances_of(project_id)) do
    if inst.parent then return inst end
  end
end

local function offsets(project_id)
  local list = rig.instances_of(project_id)
  table.sort(list, function(a, b) return a.id < b.id end)
  local seed, out = list[1], {}
  for i = 2, #list do
    out[#out + 1] = (list[i].footprint.left - seed.footprint.left) .. "," .. (list[i].footprint.top - seed.footprint.top)
  end
  table.sort(out)
  return table.concat(out, " ")
end

local function verify()
  local s = storage.plugs
  local bare
  for _, row in ipairs(rig.call("list_designs", rig.FORCE)) do
    if row.name == "Two bare plugs" then bare = row end
  end
  check.eq("plugs two plugs without numbers make an invalid design", bare and bare.error, "many-entries")
  local one, two = child_of(s.hub_projects[1]), child_of(s.hub_projects[2])
  check.eq("plugs socket 1 attaches by plug 1, unturned", one and one.direction, D.north)
  check.eq("plugs socket 2 attaches by plug 2, turned to match", two and two.direction, D.west)
  local three = rig.call("get_project", s.hub_projects[3])
  check.eq("plugs socket 3 builds no child", three and three.count, 1)
  check.eq("plugs socket 3 closes as no-plug", three and three.closed["no-plug"], 1)
  check.eq("plugs sides with sockets grow east and south", offsets(s.sides), "0,1 1,0")
  check.eq("plugs an older project grows through its socket alone", offsets(s.old), "1,0 2,0")
end

case.checks = { [1500] = verify }

return case
