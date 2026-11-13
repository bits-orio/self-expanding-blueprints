-- stop_remove.lua: stopping a project can take copies off the map with it,
-- and robots coming into reach bring parked spots back at once.
--   plain:   stop_project leaves every copy, the one under construction too
--   unbuilt: stop_project(id, "unbuilt") removes the copy robots have not
--            finished and leaves the finished one
--   all:     stop_project(id, "all") removes every copy
--   reach:   copies past the roboport's reach wait; once a network reaches
--            them they are placed within seconds

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "stop_remove" }

local STOP_REGION, REACH_REGION = 201, 202
local D = defines.direction
-- Each row at its own x, 120 tiles from the next: out of the other rows' roboport reach (55).
local ROWS = { plain = -120, unbuilt = 0, all = 120 }
local REACH_COPIES = 3
local CHEST = { { name = "iron-chest", position = { x = 0.5, y = 0.5 } } }

-- One chest for each row: its second copy stays under construction.
local function stocked(surface, o, x)
  rig.network(surface, rig.offset(o, x - 20, -20), { { "iron-chest", 1 } })
end

function case.setup(surface)
  local o = rig.region(STOP_REGION)
  rig.floor(surface, rig.box(o, -160, -40, 140, 20))
  for _, x in pairs(ROWS) do stocked(surface, o, x) end
  local r = rig.region(REACH_REGION)
  rig.floor(surface, rig.box(r, -120, -60, 60, 60))
  -- Reaches (55 tiles) the first copy of the row only.
  rig.network(surface, rig.offset(r, -54, 0), { { "iron-chest", 20 } })
  -- A second network over the whole row, another force's until the case
  -- hands it over: a roboport built then would have to charge first.
  rig.network(surface, rig.offset(r, 10, -12), { { "iron-chest", 20 } }, rig.own_force(rig.FREE_FORCE))
  storage.stop_remove = { design = rig.design(CHEST, "Stop chest") }
  check.truthy("stop_remove design registered", storage.stop_remove.design)
end

local function start(region, x, width, extra)
  local params = {
    force = rig.FORCE, surface = game.surfaces.nauvis, design = storage.stop_remove.design, charted_only = false,
    area = rig.box(rig.region(region), x, 0, x + width, 1), directions = { D.east },
  }
  for k, v in pairs(extra or {}) do params[k] = v end
  local id, reason = rig.call("start_project", params)
  check.truthy("stop_remove project starts at x = " .. x, id, reason)
  return id
end

function case.start()
  local s = storage.stop_remove
  s.projects = {}
  for name, x in pairs(ROWS) do s.projects[name] = start(STOP_REGION, x, 2, { materials = false, max_building = 2 }) end
  s.reach = start(REACH_REGION, 0, REACH_COPIES)
end

local function row(surface, x)
  local box = rig.box(rig.region(STOP_REGION), x, 0, x + 2, 1)
  return rig.count(surface, box, "iron-chest"), rig.ghosts(surface, box)
end

local function stop(surface)
  local s = storage.stop_remove
  for name, x in pairs(ROWS) do
    local built, ghosts = row(surface, x)
    check.same("stop_remove " .. name .. " has one copy built and one under construction", { built, ghosts }, { 1, 1 })
  end
  check.truthy("stop_remove plain stop", rig.call("stop_project", s.projects.plain))
  check.truthy("stop_remove stop removing the unbuilt", rig.call("stop_project", s.projects.unbuilt, "unbuilt"))
  check.truthy("stop_remove stop removing all", rig.call("stop_project", s.projects.all, "all"))
  local reach = rig.call("get_project", s.reach)
  check.truthy("stop_remove copies past the roboport's reach wait", reach and reach.count < REACH_COPIES, reach and reach.count)
  local r = rig.region(REACH_REGION)
  local near = rig.box(r, 0, -25, 20, -5)
  for _, e in pairs(surface.find_entities_filtered { area = { { near.left, near.top }, { near.right, near.bottom } }, force = rig.FREE_FORCE }) do
    e.force = rig.FORCE
  end
  s.networked = game.tick
end

local function verify(surface)
  local s = storage.stop_remove
  check.same("stop_remove a plain stop leaves both copies", { row(surface, ROWS.plain) }, { 1, 1 })
  check.same("stop_remove unbuilt: the finished copy stays alone", { row(surface, ROWS.unbuilt) }, { 1, 0 })
  check.same("stop_remove all: nothing is left", { row(surface, ROWS.all) }, { 0, 0 })
end

-- When each copy of the reach row was finished, for the log.
function case.on_event(name, payload)
  local s = storage.stop_remove
  if name ~= "on_instance_completed" or not (s and s.reach) or payload.project_id ~= s.reach then return end
  s.done = s.done or {}
  s.done[#s.done + 1] = game.tick
end

-- Soon after the network came into reach: the old ten-second timer would
-- not have come round yet.
local function reached(surface)
  local s = storage.stop_remove
  local reach = rig.call("get_project", s.reach)
  check.eq("stop_remove robots in reach build the parked copies", reach and reach.count, REACH_COPIES)
  local box = rig.box(rig.region(REACH_REGION), 0, 0, REACH_COPIES, 1)
  check.eq("stop_remove and every one of them is built", rig.count(surface, box, "iron-chest"), REACH_COPIES)
  check.info("stop_remove second network at " .. s.networked .. ", copies finished at " .. check.show(s.done))
end

case.checks = { [900] = stop, [1260] = reached, [1800] = verify }

return case
