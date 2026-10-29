-- The creeping-miner stage (the single-blueprint creep, D54): a strip of
-- iron three tiles deep and one ore a tile, so each drill runs dry in about
-- 18 seconds, with power and a sink where the belt line starts.
-- remote.call("seb-media", "creep") starts the project there.

local creep = {}

local D = defines.direction
local NAME = "Creeping miner"
creep.SCENE = { x = 900, y = 0 }
local LENGTH = 95                       -- tiles of ore east of the start, inside the cleared stage

local function belt(x)
  return { name = "transport-belt", position = { x = x, y = 1.5 }, direction = D.west }
end

-- Three belts carrying west and a pole behind a drill that drops onto them,
-- an ore sensor on the drill, a plug at the back and a socket on the drill's
-- back edge naming the design itself.
creep.DESIGN = {
  belt(0.5), belt(1.5), belt(2.5), { name = "medium-electric-pole", position = { x = 1.5, y = 0.5 } },
  { name = "electric-mining-drill", position = { x = 4.5, y = 1.5 }, direction = D.west },
  { name = "seb-sensor", position = { x = 4.5, y = 1.5 } },
  { name = "seb-entry", position = { x = 0.5, y = 1.5 }, direction = D.east },
  { name = "seb-socket", position = { x = 3.5, y = 1.5 }, direction = D.east, player_description = NAME },
}
creep.LABEL = NAME

-- The ore, the line's power and its sink (a loader into a chest).
function creep.stage(surface, force)
  local o = creep.SCENE
  for x = 3, LENGTH do
    for y = 0, 2 do
      surface.create_entity { name = "iron-ore", position = { o.x + x + 0.5, o.y + y + 0.5 }, amount = 1 }
    end
  end
  local function make(name, x, y, extra)
    local spec = { name = name, position = { o.x + x, o.y + y }, force = force }
    for k, v in pairs(extra or {}) do spec[k] = v end
    return surface.create_entity(spec)
  end
  local eei = make("electric-energy-interface", -4, -3)
  eei.power_production, eei.electric_buffer_size = 1e9, 1e10
  make("medium-electric-pole", -2.5, -0.5)
  make("transport-belt", -0.5, 1.5, { direction = D.west })
  make("loader-1x1", -1.5, 1.5, { direction = D.west, type = "input" })
  make("infinity-chest", -2.5, 1.5).remove_unfiltered_items = true
end

-- Starts the creep at the stage's start, with "Replace buildings in the way".
function creep.start(design)
  local o = creep.SCENE
  return remote.call("self-expanding-blueprints", "start_project", {
    force = "player", surface = game.surfaces.nauvis, design = design, charted_only = false, superforce = true,
    area = { { o.x, o.y }, { o.x + LENGTH, o.y + 3 } },
  })
end

return creep
