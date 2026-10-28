-- S2 marker settings spike.
-- on_init (during --create) only builds the rig: events raised inside on_init are not delivered,
-- so every case runs at tick 60 of the benchmark, like a real stamp would. Later on_nth_tick calls
-- watch the cases that need the game to run (robots, wires).
local lib = require("lib")

local QUESTIONS = {
  require("q1"),
  require("q2"),
  require("q3"),
  require("q4"),
  require("q5"),
  require("q6"),
  require("q7"),
  require("q8"),
  require("q9"),
  require("qx"),
}

local RUN_TICK = 60

script.on_init(function()
  lib.rig()
  lib.log("INIT_DONE tick=" .. game.tick)
end)

script.on_event(defines.events.script_raised_built, lib.on_script_raised_built)
script.on_event(defines.events.on_blueprint_settings_pasted, lib.on_settings_pasted)

script.on_nth_tick(60, function(e)
  if e.tick == RUN_TICK then
    local ctx = {surface = game.surfaces.nauvis}
    for _, q in ipairs(QUESTIONS) do
      lib.case(q.id, function() q.run(ctx) end)
    end
    lib.log("RUN_DONE tick=" .. game.tick)
  elseif e.tick > RUN_TICK then
    for _, q in ipairs(QUESTIONS) do
      if q.on_tick then lib.case(q.id .. " tick", function() q.on_tick(e) end) end
    end
  end
end)
