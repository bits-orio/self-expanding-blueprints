-- Spike S8: does anything chart in a headless run? A powered radar, a
-- scripted chart, chart_all, and the force's spawn area, over 2000 ticks.
local function say(...) log("SEB_SPIKE " .. table.concat({ ... }, " ")) end

local function charted(f, s, cx, cy) return tostring(f.is_chunk_charted(s, { cx, cy })) end

script.on_init(function()
  local s = game.surfaces.nauvis
  s.request_to_generate_chunks({ 800, 800 }, 4)
  s.request_to_generate_chunks({ -800, -800 }, 4)
  s.force_generate_chunk_requests()
  local f = game.forces.player
  local eei = s.create_entity { name = "electric-energy-interface", position = { 800, 790 }, force = f }
  eei.power_production, eei.electric_buffer_size = 1e9, 1e10
  s.create_entity { name = "medium-electric-pole", position = { 800, 794 }, force = f }
  s.create_entity { name = "radar", position = { 800, 797 }, force = f }
  say("init spawn chunk (0,0)", charted(f, s, 0, 0), "radar chunk (25,24)", charted(f, s, 25, 24))
end)

script.on_nth_tick(1, function(e)
  local s, f = game.surfaces.nauvis, game.forces.player
  if e.tick == 3 then f.chart(s, { { -810, -810 }, { -780, -780 } }) end
  if e.tick == 4 then f.chart_all(s) end
  if e.tick % 250 == 0 and e.tick <= 2000 then
    say("tick", e.tick, "spawn", charted(f, s, 0, 0), "radar", charted(f, s, 25, 24), "scripted", charted(f, s, -25, -25),
      "visible radar", tostring(f.is_chunk_visible(s, { 25, 24 })))
  end
end)
