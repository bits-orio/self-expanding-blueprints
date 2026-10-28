-- Gates hold a stamp back without closing its socket: the socket waits and
-- is tried again. Concurrency reopens on instance completion; materials have
-- no engine event for "items arrived", so a materials wait retries on a timer.

local const = require("scripts.const")
local limits = require("scripts.core.limits")
local registry = require("scripts.core.registry")

local gates = {}

local STATE = const.PROJECT_STATE

-- The network whose robots can build at `position`, preferring the one with
-- the most idle construction robots.
function gates.network_at(surface, force, position)
  local best
  for _, network in pairs(surface.find_logistic_networks_by_construction_area(position, force)) do
    if not best or network.available_construction_robots > best.available_construction_robots then
      best = network
    end
  end
  return best
end

-- On a space platform the hub builds every ghost from its own inventory:
-- there are no robots and no network there, and the hub is the supply.
local function hub_of(surface)
  local platform = surface.platform
  local hub = platform and platform.valid and platform.hub
  return hub and hub.valid and hub or nil
end

-- What a stamp at `position` is built from: the construction network
-- reaching it, or a platform's hub inventory (both count items alike), or
-- nil when nothing builds there.
function gates.supply_at(surface, force, position)
  local hub = hub_of(surface)
  if hub then return hub.get_inventory(defines.inventory.hub_main) end
  return gates.network_at(surface, force, position)
end

-- The first item the supply cannot spare, as {name, quality, count (what
-- the stamp needs), have (what the supply can spare)}, or nil.
local function short_of(supply, cost, reserve)
  for _, item in ipairs(cost) do
    local spare = supply.get_item_count({ name = item.name, quality = item.quality }) - (reserve or 0)
    if spare < item.count then
      return { name = item.name, quality = item.quality, count = item.count, have = math.max(0, spare) }
    end
  end
end

-- Adds `count` of an item and quality to a cost list, on its line if it
-- has one (`lines` by item and quality), so the gate counts them together.
local function add_line(cost, lines, name, quality, count)
  local key = name .. "/" .. (quality or "normal")
  local line = lines[key]
  if not line then
    line = { name = name, quality = quality, count = 0 }
    lines[key] = line
    cost[#cost + 1] = line
  end
  line.count = line.count + count
end

-- Whether the stamp at the spot takes more than the design costs, as
-- checks.obstacles found: explosives for the cliffs the robots must blow up
-- first (spot.cliffs, when the force can remove cliffs), or the landfill the
-- engine lays under it on water (spot.cover, superforced), each
-- {[item] = count}.
function gates.adds_cost(spot)
  return (spot.cliffs ~= nil and next(spot.cliffs) ~= nil) or (spot.cover ~= nil and next(spot.cover) ~= nil)
end

-- What a stamp at the spot takes from its supply: the design's cost, and
-- those explosives and that landfill.
function gates.cost_of(spot)
  if not gates.adds_cost(spot) then return spot.prepared.cost end
  local cost, lines = {}, {}
  for _, item in ipairs(spot.prepared.cost) do add_line(cost, lines, item.name, item.quality, item.count) end
  for explosive, count in pairs(spot.cliffs or {}) do add_line(cost, lines, explosive, "normal", count) end
  for item, count in pairs(spot.cover or {}) do add_line(cost, lines, item, "normal", count) end
  return cost
end

-- true, or false with a reason (and for missing materials the first
-- missing item).
function gates.materials(surface, force, position, cost, reserve)
  local supply = gates.supply_at(surface, force, position)
  if not supply then return false, const.REASON.no_network end
  if supply.object_name == "LuaLogisticNetwork" and not gates.robots_idle(supply) then
    return false, const.REASON.robots_busy
  end
  local missing = short_of(supply, cost, reserve)
  if missing then return false, const.REASON.missing_materials, missing end
  return true
end

-- Copies stalled where no robots reach: a first copy may go down out of
-- reach (growth.lua), and it must not hold a slot until someone builds it.
local function unreachable(project)
  local n = 0
  for _, reason in pairs(project.stalled or {}) do
    if reason == const.REASON.no_network then n = n + 1 end
  end
  return n
end

-- Copies under construction now of the force's live projects (a stopped
-- project no longer counts the copies it left behind).
local function force_building(force_index)
  local n = 0
  for id in pairs(registry.project_ids(force_index)) do
    local project = storage.projects[id]
    if project and project.state ~= STATE.stopped then n = n + project.building - unreachable(project) end
  end
  return n
end

-- How many more copies the force may have in flight under the map's cap
-- (limits "building"; no cap is math.huge): the force's projects' copies
-- under construction and the ones its blueprint builders stamped
-- (storage.stamps_in_flight, kept by the Stamp verb) count alike.
local function force_room(force_index)
  local cap = limits.of(force_index, "building")
  if cap == 0 then return math.huge end
  local stamps = storage.stamps_in_flight and storage.stamps_in_flight[force_index] or 0
  return cap - force_building(force_index) - stamps
end

-- Room under the force's cap for one more copy in flight.
function gates.force_has_room(force_index)
  return force_room(force_index) > 0
end

-- How many more copies the project may put in flight now: within its own
-- cap and the force's. An advance asks once and counts its own stamps
-- down, so a step never walks the force's projects. A dry run builds
-- nothing and is never held.
function gates.room(project)
  if project.dry_run then return math.huge end
  local own = (project.gates.max_building or const.MAX_BUILDING) - project.building
  if own <= 0 then return 0 end
  return math.min(own, force_room(project.force_index))
end

-- Whether the force may start another project (limits "projects"): its
-- projects growing or paused count, and a plan never does.
function gates.may_start(force_index)
  local cap = limits.of(force_index, "projects")
  if cap == 0 then return true end
  local active = 0
  for id in pairs(registry.project_ids(force_index)) do
    local project = storage.projects[id]
    if project and not project.dry_run and (project.state == STATE.growing or project.state == STATE.paused) then
      active = active + 1
    end
  end
  return active < cap
end

-- Enough of the network's construction robots idle (seb-idle-robot-share
-- percent), so growth leaves room for the team's own building.
function gates.robots_idle(network)
  local share = settings.global["seb-idle-robot-share"].value
  if share == 0 then return true end
  local all = network.all_construction_robots
  return all == 0 or network.available_construction_robots * 100 >= share * all
end

return gates
