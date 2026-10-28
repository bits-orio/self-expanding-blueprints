-- fix_builders_many.lua: 3,000 unwired builders of a team limited to 50
-- (region 136, DESIGN.md D44 and D45). The ones past the limit show the
-- limit error from the start, and nothing looks at them again until a
-- place comes free. INFO lines, for whoever reads the log: how long placing
-- them takes, the ticks around the builders timer (a tick it makes long
-- shows as one gap among the others), lifting the limit for all that wait,
-- and releasing the team.

local check = require("lib.check")
local rig = require("lib.rig")
local builders = require("lib.builders")

local case = { name = "fix_builders_many" }

local REGION = 136
local BUILDERS, WORKING, COLUMNS, PITCH = 3000, 50, 80, 3
local WINDOW = 120   -- ticks looked at, two periods of the timer's once a second

local function state()
  return storage.fix_builders_many
end

-- In a grid, in one tick.
function case.setup(surface)
  local o = rig.region(REGION)
  rig.floor(surface, rig.box(o, -125, -60, 125, 60))
  local force = rig.own_force("seb-fb-many")
  rig.call("set_limits", force, { builders = WORKING })
  local list, placing = {}, helpers.create_profiler()
  for i = 0, BUILDERS - 1 do
    list[i + 1] = surface.create_entity { name = "seb-builder", force = force, raise_built = true,
      position = { o.x - 118.5 + (i % COLUMNS) * PITCH, o.y - 55 + math.floor(i / COLUMNS) * PITCH } }
  end
  placing.stop()
  log({ "", "SEB_TEST INFO fix_builders many: placed ", BUILDERS, " builders in ", placing })
  storage.fix_builders_many = { force = force, origin = o, list = list }
end

local function refused(from, to)
  local n = 0
  for i = from, to do
    if builders.output(state().list[i])["virtual/seb-error-limit"] == 1 then n = n + 1 end
  end
  return n
end

local function shown()
  check.eq("fix_builders many: the first builders take requests", refused(1, WORKING), 0)
  check.eq("fix_builders many: all the others show the limit error", refused(WORKING + 1, BUILDERS), BUILDERS - WORKING)
end

-- The gap between one tick's handler and the next's.
local gaps = {}

local function print_gaps()
  for first = 1, #gaps, 9 do
    local line = { "" }
    for i = first, math.min(first + 8, #gaps) do line[#line + 1], line[#line + 2] = " ", gaps[i] end
    log({ "", "SEB_TEST INFO fix_builders many: gaps from tick ", first, " on:", line })
  end
end

local function note_gap()
  if gaps[#gaps] then gaps[#gaps].stop() end
  if #gaps >= WINDOW then
    script.on_nth_tick(1, nil)
    return print_gaps()
  end
  gaps[#gaps + 1] = helpers.create_profiler()
end

local function window()
  gaps = {}
  script.on_nth_tick(1, note_gap)
end

-- The limit lifted: every builder that waited takes a place.
local function raise()
  local raising = helpers.create_profiler()
  rig.call("set_limits", state().force, { builders = 0 })
  raising.stop()
  log({ "", "SEB_TEST INFO fix_builders many: lifted the limit for ", BUILDERS - WORKING, " waiting builders in ", raising })
end

local function release()
  local id = remote.call("mts-v1", "get_event_id", "on_team_released")
  local releasing = helpers.create_profiler()
  script.raise_event(id, { force_name = state().force })
  releasing.stop()
  log({ "", "SEB_TEST INFO fix_builders many: released the team of ", BUILDERS, " builders in ", releasing })
end

local function released(surface)
  local m = state()
  check.eq("fix_builders many: a released team's builders lose their outputs",
    rig.count(surface, rig.box(m.origin, -125, -60, 125, 60), "seb-builder-output"), 0)
end

case.checks = { [120] = shown, [10740] = window, [10980] = raise, [11100] = release, [11160] = released }

return case
