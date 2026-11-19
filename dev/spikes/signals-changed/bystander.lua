-- A second mod polling the same lamp connector as the probe: every tick
-- without a tick argument, and every 60 ticks with the tick of its own last
-- poll. run.sh makes two mods from this file, s0-probe (its handlers run
-- before the probe's) and sz-probe (after), by filling in NAME.
local NAME = "@NAME@"
local RED = defines.wire_connector_id.circuit_red
log("SC " .. NAME .. " parsed")
local last = 0
script.on_event(defines.events.on_tick, function(e)
  local lamp = game.surfaces.nauvis.find_entities_filtered { name = "small-lamp", position = { 2, 0 }, radius = 1.5 }[1]
  if not lamp then return end
  local changed = lamp.get_signals_changed(RED)
  if (e.tick >= 19 and e.tick <= 24) or (e.tick >= 40 and e.tick <= 42) or (e.tick >= 139 and e.tick <= 142) then
    log("SC " .. NAME .. " tick=" .. e.tick .. " lamp_red_changed=" .. tostring(changed))
  end
  if e.tick % 60 == 0 then
    log("SC " .. NAME .. " POLL60 tick=" .. e.tick .. " arg_last=" .. last .. " -> "
      .. tostring(lamp.get_signals_changed(RED, last)) .. " (no-arg " .. tostring(changed) .. ")")
    last = e.tick
  end
end)
