-- clear.lua: Keep clear tiles, and Negative Space's markers read as them.
--   lane:      a column of Keep clear past a design's edge stays an empty
--              lane between copies, and a tree on it is cleared
--   building:  a chest on a Keep clear tile stops the copy; superforced,
--              the chest is marked for removal and the copy is built
--   alias:     a design carrying Negative Space's markers grows: they are no
--              part of it (not in its materials, never left as ghosts), the
--              plain one keeps its tile clear, the automatic one is ignored

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "clear" }

local LANE, BUILDING, ALIAS = 57, 58, 59
local D = defines.direction

local function column(name, x)
  local list = {}
  for y = 0, 2 do list[#list + 1] = { name = name, position = { x = x, y = y + 0.5 } } end
  return list
end

local function with(parts, extra)
  local list = {}
  for _, e in ipairs(parts) do list[#list + 1] = e end
  for _, e in ipairs(extra) do list[#list + 1] = e end
  return list
end

local function start(design, region, left, right, extra)
  local o = rig.region(region)
  local params = {
    force = rig.FORCE, surface = game.surfaces.nauvis, design = design, charted_only = false,
    area = rig.box(o, left, 0, right, 3), directions = { D.east },
  }
  for k, v in pairs(extra or {}) do params[k] = v end
  local id, reason = rig.call("start_project", params)
  check.truthy("clear project starts", id, reason)
  return id
end

local function chest(surface, region, x)
  return surface.create_entity { name = "iron-chest", position = rig.offset(rig.region(region), x, 1.5), force = rig.FORCE }
end

function case.setup(surface)
  for _, region in ipairs({ LANE, BUILDING, ALIAS }) do rig.site(surface, region) end
  local panel = { rig.panel(1.5, 1.5) }
  storage.clear = {
    lane = rig.design(with(panel, column("seb-keep-clear", 3.5)), "Clear lane"),
    alias = rig.design(with(with(panel, column("negative-space", 3.5)), { { name = "negative-space-auto", position = { x = 1.5, y = 3.5 } } }), "Clear alias"),
    tree = surface.create_entity { name = "tree-01", position = rig.offset(rig.region(LANE), 7.5, 1.5) },
    blocked = chest(surface, BUILDING, 3.5),
    forced = chest(surface, BUILDING, 13.5),
    alias_blocked = chest(surface, ALIAS, 23.5),
  }
end

function case.start()
  local c = storage.clear
  c.lane_project = start(c.lane, LANE, 0, 12, { max_instances = 3 })
  c.blocked_project = start(c.lane, BUILDING, 0, 4, { max_instances = 1 })
  c.forced_project = start(c.lane, BUILDING, 10, 14, { max_instances = 1, superforce = true })
  c.alias_project = start(c.alias, ALIAS, 0, 8, { max_instances = 2 })
  c.alias_blocked_project = start(c.alias, ALIAS, 20, 24, { max_instances = 1 })
end

local function lane_kept(surface)
  local c = storage.clear
  local o = rig.region(LANE)
  local lane = rig.call("get_project", c.lane_project)
  check.eq("clear lane copies built", lane and lane.count, 3)
  check.eq("clear lane panels where the lane leaves room", rig.count(surface, rig.box(o, 0, 0, 12, 3), "solar-panel"), 3)
  for _, x in ipairs({ 3, 7, 11 }) do
    check.eq("clear lane tile x=" .. x .. " left empty", surface.count_entities_filtered {
      area = { { o.x + x + 0.1, o.y + 0.1 }, { o.x + x + 0.9, o.y + 2.9 } }, type = { "solar-panel", "entity-ghost" } }, 0)
  end
  check.truthy("clear lane tree on it cleared", not c.tree.valid or c.tree.to_be_deconstructed())
  local blocked = rig.call("get_project", c.blocked_project)
  check.eq("clear building on a kept tile stops the copy", blocked and blocked.count, 0)
  check.eq("clear the chest is left alone", c.blocked.valid and c.blocked.to_be_deconstructed(), false)
  local forced = rig.call("get_project", c.forced_project)
  check.eq("clear superforced copy built over a kept tile", forced and forced.count, 1)
  check.truthy("clear superforced chest marked for removal", not c.forced.valid or c.forced.to_be_deconstructed())
  local alias = rig.call("get_project", c.alias_project)
  check.eq("clear Negative Space design grows", alias and alias.count, 2)
  local copies = rig.instances_of(c.alias_project)
  check.eq("clear Negative Space copies complete", copies[2] and copies[2].state, "complete")
  local a = rig.region(ALIAS)
  local box = { { a.x - 1, a.y - 1 }, { a.x + 30, a.y + 6 } }
  check.eq("clear no Negative Space ghost left", surface.count_entities_filtered { area = box, ghost_name = { "negative-space", "negative-space-auto" } }, 0)
  check.eq("clear Negative Space tile refuses a chest", rig.call("get_project", c.alias_blocked_project).count, 0)
end

case.checks = { [2400] = lane_kept }

return case
