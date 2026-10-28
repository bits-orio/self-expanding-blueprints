-- S3 tracking coverage spike: wiring only. See cases.lua for the questions.
local lg = require("lg")
local rig = require("rig")
local track = require("track")
local sched = require("sched")
local cases = require("cases")
local events = require("events")

events.register()

sched.tasks.stamp_all = function() cases.stamp_all() end
sched.tasks.platform_setup = function() cases.platform_setup() end

script.on_init(function()
  track.init()
  storage.done = {}
  storage.ev_count = {}
  storage.verbose_areas = {}
  rig.build(game.surfaces.nauvis)
  -- The platform is created at runtime (tick 2), as SRB's tests do, not during --create.
  if script.active_mods["space-age"] then sched.at(2, "platform_setup") end
  sched.at(5, "stamp_all")
  lg.out("INIT space_age=" .. tostring(script.active_mods["space-age"] ~= nil))
end)

script.on_event(defines.events.on_tick, function(e)
  sched.run(e.tick)
  if e.tick % 60 == 0 then cases.watch_C() end
  if e.tick % 120 == 0 then cases.watch_retiring() end
  if e.tick % 600 == 0 then cases.status() end
  cases.check_all_done()
end)
