-- water_floors.lua (Space Age only; base runs skip it): the other planets'
-- liquid floors are water to a copy too (D52), on cases.water's force with
-- foundation and Aquilo researched here (region 184).
--   lava -> foundation, oil ocean -> foundation, ammoniacal ocean -> ice
--   platform. On each, a plain copy closes "water" and nothing is laid; a
--   superforced one waits for the 9 of the cover the engine lays under it,
--   and once they arrive is built on them (the floor hidden under the
--   cover); without the research (rig.FORCE) a superforced copy closes
--   "water".

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "water_floors" }

local REGION = 184
local FORCE = "seb-water"
local CELL = { rig.panel(1.5, 1.5) }
-- Each floor fills x 10..30 of a 20-tile band starting at `top`.
local FLOORS = {
  { tile = "lava", cover = "foundation", top = -40 },
  { tile = "oil-ocean-shallow", cover = "foundation", top = -10 },
  { tile = "ammoniacal-ocean", cover = "ice-platform", top = 20 },
}

local function band(o, f) return rig.box(o, 10, f.top, 30, f.top + 20) end

function case.setup(surface)
  if not script.active_mods["space-age"] then return end
  rig.own_force(FORCE)
  for _, tech in ipairs({ "foundation", "planet-discovery-aquilo" }) do game.forces[FORCE].technologies[tech].researched = true end
  local o = rig.region(REGION)
  rig.floor(surface, rig.box(o, -60, -60, 60, 60))
  for _, f in ipairs(FLOORS) do rig.floor(surface, band(o, f), f.tile) end
  storage.water_floors = {
    chest = rig.network(surface, rig.offset(o, -25, 0), { { "solar-panel", 20 } }, FORCE),
    cell = rig.call("register_design", FORCE, rig.blueprint(CELL, { label = "Floors cell" })),
    bare = rig.design(CELL, "Floors bare cell"), projects = {},
  }
end

local function start(force, design, at, extra)
  local params = { force = force, surface = game.surfaces.nauvis, design = design, point = at, charted_only = false,
    max_instances = 1, materials = false }
  for k, v in pairs(extra or {}) do params[k] = v end
  local id, reason = rig.call("start_project", params)
  check.truthy("water_floors project starts at " .. at.x .. "," .. at.y, id, reason)
  return id
end

function case.start()
  local s = storage.water_floors
  if not s then return end
  local o = rig.region(REGION)
  for i, f in ipairs(FLOORS) do
    s.projects[i] = {
      gate = start(FORCE, s.cell, rig.offset(o, 14.5, f.top + 5.5), { superforce = true, materials = true }),
      plain = start(FORCE, s.cell, rig.offset(o, 24.5, f.top + 5.5)),
      bare = start(rig.FORCE, s.bare, rig.offset(o, 24.5, f.top + 15.5), { superforce = true }),
    }
  end
end

local function closed_at_water(label, id)
  local p = rig.call("get_project", id) or {}
  local none = p.nothing_built or {}
  check.same("water_floors " .. label .. " closes at water", { p.count, p.closed and p.closed.water, none.reason }, { 0, 1, "water" })
end

local function waiting(surface)
  local s = storage.water_floors
  if not s then return end
  local o = rig.region(REGION)
  for i, f in ipairs(FLOORS) do
    local p = s.projects[i]
    closed_at_water(f.tile .. " plain", p.plain)
    closed_at_water(f.tile .. " without the research", p.bare)
    local lake = band(o, f)
    local laid = surface.count_entities_filtered { area = { { lake.left + 10, lake.top }, { lake.right, lake.bottom } }, type = "tile-ghost" }
    check.eq("water_floors " .. f.tile .. " plain lays nothing", laid, 0)
    local g = rig.call("get_project", p.gate) or {}
    local item = g.status and g.status.item or {}
    check.same("water_floors " .. f.tile .. " superforced waits for " .. f.cover, { g.count, g.gate, item.name, item.count },
      { 0, "missing-materials", f.cover, 9 })
    s.chest.insert { name = f.cover, count = 9 }
  end
end

local function built(surface)
  local s = storage.water_floors
  if not s then return end
  for i, f in ipairs(FLOORS) do
    local copy = rig.instances_of(s.projects[i].gate)[1]
    check.eq("water_floors " .. f.tile .. " superforced copy built", copy and copy.state, "complete")
    if copy then
      local fp = copy.footprint
      local on = 0
      for _, tile in pairs(surface.find_tiles_filtered { area = { { fp.left, fp.top }, { fp.right, fp.bottom } }, name = f.cover }) do
        if tile.hidden_tile == f.tile then on = on + 1 end
      end
      check.eq("water_floors " .. f.tile .. " copy stands on " .. f.cover, on, 9)
    end
  end
end

case.checks = { [600] = waiting, [3000] = built }

return case
