-- seeds.lua: a project whose first copy is not stamped yet holds its seed's
-- spot (D57), so a quick second click cannot start a project on top of it:
-- one started on it in the same tick is refused seed-occupied, while one
-- right beside it starts, and both grow.

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "seeds" }

local REGION = 192
local CELL = { rig.panel(1.5, 1.5) }

local function start(dx)
  return rig.call("start_project", {
    force = rig.FORCE, surface = game.surfaces.nauvis, design = storage.seeds.cell, charted_only = false,
    position = rig.offset(rig.region(REGION), dx, 0.5), max_instances = 1,
  })
end

function case.setup(surface)
  rig.site(surface, REGION)
  storage.seeds = { cell = rig.design(CELL, "Seeds cell") }
  check.truthy("seeds design registered", storage.seeds.cell)
end

function case.start()
  local s = storage.seeds
  s.first = start(0.5)
  local again, why = start(0.5)
  s.beside = start(3.5)
  check.truthy("seeds first project starts", s.first)
  check.truthy("seeds same spot in the same tick refused", again == nil and why == "seed-occupied", why)
  check.truthy("seeds project right beside starts", s.beside)
end

local function grown()
  local s = storage.seeds
  for _, id in ipairs({ s.first, s.beside }) do
    local p = rig.call("get_project", id)
    check.eq("seeds project " .. tostring(id) .. " built its copy", p and p.count, 1)
  end
end

case.checks = { [900] = grown }

return case
