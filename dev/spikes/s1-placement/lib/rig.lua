-- Test zones: generated chunks, flat tiles, no entities, no enemies.
local fmt = require("lib.fmt")
local R = {}

function R.prepare(surface, cx, cy, r, tile)
  surface.request_to_generate_chunks({x = cx, y = cy}, math.ceil(r / 32) + 1)
  surface.force_generate_chunk_requests()
  local area = {{cx - r, cy - r}, {cx + r, cy + r}}
  for _, e in pairs(surface.find_entities_filtered({area = area})) do
    if e.valid and e.type ~= "character" then e.destroy() end
  end
  local tiles, n = {}, 0
  for x = cx - r, cx + r - 1 do
    for y = cy - r, cy + r - 1 do
      n = n + 1
      tiles[n] = {name = tile or "lab-dark-1", position = {x = x, y = y}}
    end
  end
  surface.set_tiles(tiles)
  surface.destroy_decoratives({area = area})
  local left = surface.count_entities_filtered({area = area})
  fmt.out("RIG zone", surface.name, fmt.p({x = cx, y = cy}), "r=" .. r, "tile=" .. (tile or "lab-dark-1"),
    "entities_left=" .. left)
end

function R.init()
  game.map_settings.enemy_expansion.enabled = false
  game.forces.enemy.kill_all_units()
  if not game.forces["seb-other"] then game.create_force("seb-other") end
  local s = game.surfaces.nauvis
  R.prepare(s, 0, 0, 160)
  R.prepare(s, 2000, -3001, 48)
  R.prepare(s, -99999, 100001, 48)
  R.prepare(s, 0, 400, 48, "grass-1")
  R.prepare(s, 600, 0, 96)
  R.prepare(s, 1200, 0, 128)
  R.prepare(s, -600, 0, 80)
  fmt.out("RIG charted_chunks_player_nauvis_origin", tostring(game.forces.player.is_chunk_charted(s, {0, 0})))
end

return R
