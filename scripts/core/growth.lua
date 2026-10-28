-- One step of the growth loop: try the next open socket of a project.
--   resolve the target design -> place it -> rules -> overlap -> on the map
--   (spots.lua: terrain -> probes -> obstacles -> materials gate -> stamp)
-- A socket either produces a stamp, closes with a reason, or waits at a
-- gate until something changes (most gates hold the project at the socket;
-- loop.lua sets a few sockets aside on their own). Every design tried pays
-- for the work it did (work.lua).

local const = require("scripts.const")
local geometry = require("scripts.core.geometry")
local depletion = require("scripts.core.depletion")
local library = require("scripts.core.library")
local twins = require("scripts.core.twins")
local placement = require("scripts.core.placement")
local footprints = require("scripts.core.footprints")
local pools = require("scripts.core.pools")
local plan = require("scripts.core.plan")
local spots = require("scripts.core.spots")
local walk = require("scripts.core.walk")
local work = require("scripts.core.work")

local growth = {}

local REASON = const.REASON
local STATE = const.STATE
local closed = spots.closed

-- A design's parts (work.lua), as the loop paces a stamp by them.
growth.parts = work.parts

-- The copy a socket grows from: an instance, or a planned copy of a dry run.
local function parent_of(project, socket)
  if not socket.from then return nil end
  return storage.instances[socket.from] or plan.get(project, socket.from)
end

-- A parent retired for depletion still parents its own sockets: its
-- footprint, repeat and socket places outlive it, and that is the point of
-- growing on from a mined-out copy.
local function parent_removed(project, socket)
  if not socket.from then return false end
  local parent = parent_of(project, socket)
  -- A retired copy's record is forgotten once nothing needs it (D45).
  if not parent then return true end
  if parent.retired_for == "depleted" then return false end
  return parent.state == STATE.retiring or parent.state == STATE.retired
end

-- The designs a socket may stamp, in the order to try them: its project's
-- design, the parent's (an empty drawn socket), the design it names, or
-- else every design of the pool it names (pools.lua).
local function named(force_index, socket)
  local design = library.find(force_index, socket.target.name)
  if design then return { design } end
  return pools.designs(force_index, socket.target.name) or {}
end

-- A flipped project grows every design as its mirror twin (twins.lua); one
-- that cannot be mirrored is left out.
local function oriented(project, designs)
  if not project.mirrored then return designs end
  local list = {}
  for _, design in ipairs(designs) do list[#list + 1] = twins.of(design) end
  return list
end

function growth.candidates(project, socket)
  local force_index = project.force_index
  if socket.kind ~= "drawn" then return { library.get(force_index, project.design_id) } end
  if socket.target.kind == "named" then return oriented(project, named(force_index, socket)) end
  local parent = parent_of(project, socket)
  return { parent and library.get(force_index, parent.design_id) }
end

-- The build position and direction, or nil and the reason there is none.
local function place(project, socket, prepared)
  if socket.kind == "seed" then return socket.position, socket.direction end
  if socket.kind == "drawn" then return placement.on_socket(prepared, socket) end
  local parent = parent_of(project, socket)
  if not parent then return nil, REASON.invalid_design end
  return placement.implicit_child(prepared, parent, socket.toward)
end

-- A child whose footprint meets the stamp it grows from, `alone` when no
-- other stamp is in its way. A superforcing project grows it over its
-- parent: the parent's parts in its way are replaced like any of the
-- force's buildings (the map checks and the paste see to them, D54). Else a
-- parent going for depletion is waited for, so the copy after a miner goes
-- where the miner stood; and a parent staying means the child can never fit
-- (its socket sits inside the parent). Another stamp in the way: joined.
local function over_parent(project, parent, alone)
  if project.superforce then
    if alone then return nil end
    return closed(REASON.joined)
  end
  if not depletion.going(parent) then return closed(REASON.overlaps_parent) end
  if not alone then return closed(REASON.joined) end
  return spots.gate(REASON.parent_retiring)
end

-- A child meeting no stamp fits; one meeting others than its parent joined.
local function overlap(project, socket, footprint)
  local ids = footprints.overlapping(project.surface_index, footprint)
  if #ids == 0 then return nil end
  local parent
  for _, id in ipairs(ids) do
    if id == socket.from then parent = storage.instances[id] end
  end
  if not parent then return closed(REASON.joined) end
  return over_parent(project, parent, #ids == 1)
end

-- A plan mines nothing and opens a copy's sockets at once. A child is
-- planned over its planned parent where the real one would stand over it:
-- the project superforces, or it retires depleted copies and the parent
-- would be going once mined out (depletion.mined_out_goes). The parent's
-- id, or nil.
local function parent_gives_way(project, socket)
  local parent = socket.from and plan.get(project, socket.from)
  if not parent then return nil end
  if project.superforce or (project.rules.retire_depleted and parent.mined_out_goes) then return socket.from end
  return nil
end

-- Whether every corner of the footprint lies within `radius` of the seed.
local function within(footprint, center, radius)
  for _, x in ipairs({ footprint.left, footprint.right }) do
    for _, y in ipairs({ footprint.top, footprint.bottom }) do
      if (x - center.x) ^ 2 + (y - center.y) ^ 2 > radius * radius then return false end
    end
  end
  return true
end

-- Whether the project has every copy it may have: its count, or a plan's
-- limit. No socket or design changes that, so it is asked before either is
-- looked at, and every socket left says so alike.
local function reached(project)
  local max = project.rules.max_instances
  if max and project.count >= max then return true end
  return project.dry_run == true and plan.count(project) >= plan.LIMIT
end

local function check_rules(project, socket, footprint)
  local rules = project.rules
  if rules.radius and project.seed_position and not within(footprint, project.seed_position, rules.radius) then
    return closed(REASON.outside_area)
  end
  if project.dry_run then
    local hit = plan.overlaps(project, footprint, parent_gives_way(project, socket))
    if hit then return closed(hit == socket.from and REASON.overlaps_parent or REASON.joined) end
  end
  if rules.area and not geometry.contains_box(rules.area, footprint) then return closed(REASON.outside_area) end
  return overlap(project, socket, footprint)
end

-- Places the design, checks the rules, then the map (spots.lua); the spot
-- carries the try's record of its work.
local function place_and_check(project, socket, design, tally)
  local prepared = design.prepared
  if not (prepared and prepared.ok) then return closed(REASON.invalid_design, socket.position) end
  local position, direction = place(project, socket, prepared)
  if not position then return closed(direction or REASON.invalid_design, socket.position) end
  -- Superforced, a copy also stands on water, on the engine's landfill (water.lua).
  local spot = {
    design = design, prepared = prepared, position = position, direction = direction,
    footprint = placement.footprint(prepared, position, direction),
    entry_target = placement.entry_at(prepared, position, direction), work = tally,
    superforce = project.superforce, cover_water = project.superforce,
  }
  -- The rules walk the copies' overlap index chunk by chunk, a plan its own too.
  tally.chunks = spots.chunks(spot.footprint) * (project.dry_run and 2 or 1)
  local verdict = check_rules(project, socket, spot.footprint)
  if verdict then return verdict end
  return spots.on_map(project, socket, spot)
end

-- One candidate design at a socket, with the record of what trying it did
-- (`work`) and the parts and tiles its obstacle check looked at (`checked`).
local function try_design(project, socket, design)
  local tally = work.new { spots = 1 }
  local result = place_and_check(project, socket, design, tally)
  result.work, result.checked = tally, tally.checked
  return result
end

-- A result before any design was tried: nothing to charge.
local function untried(result)
  result.work, result.checked = work.new(), 0
  return result
end

-- Where the next copy at `socket` would go, for the overlay: the footprint
-- of the first design the socket would stamp, or nil when a rule already
-- rules the spot out (count reached, outside the area, a copy already
-- there). Nothing is checked on the map, so a spot shown may still turn out
-- blocked when it is tried.
function growth.preview(project, socket)
  if reached(project) then return nil end
  local design = growth.candidates(project, socket)[1]
  local prepared = design and design.prepared
  if not (prepared and prepared.ok) then return nil end
  local position, direction = place(project, socket, prepared)
  if not position then return nil end
  local footprint = placement.footprint(prepared, position, direction)
  if check_rules(project, socket, footprint) then return nil end
  return footprint
end

-- Returns {kind = "stamped", instance, spot} | {kind = "planned", spot} |
-- {kind = "closed", reason, position} | {kind = "gate", reason, item}, each
-- with `checked`, the parts and tiles checked over the designs tried, and
-- `work`, the record of what the last design tried did, for the caller to
-- charge (work.lua; any before it are paid for already). A pool's designs
-- are tried in turn (walk.lua); a step of a pool that stops early is the
-- busy gate, and the next step goes on with the next design. A count
-- reached closes every socket alike.
function growth.try(project, socket)
  if reached(project) then return untried(closed(REASON.count_reached, socket.position)) end
  if parent_removed(project, socket) then return untried(closed(REASON.parent_retired, socket.position)) end
  return walk.designs(project, socket, growth.candidates(project, socket), try_design)
end

-- One stamp outside any project (the remote stamp), with the same checks.
-- `where` holds position or build_position, as for a seed (placement.seed).
-- ctx: force_index, surface_index, design_id, charted_only, materials,
-- superforce (buildings in the way are marked for removal), generate
-- (default true off charted land; a blueprint builder passes false, D43).
function growth.stamp_once(ctx, where, direction)
  local design = library.get(ctx.force_index, ctx.design_id)
  if not (design and design.prepared and design.prepared.ok) then return untried(closed(REASON.invalid_design)) end
  local position, reason = placement.seed(design.prepared, where, direction)
  if not position then return untried(closed(reason, where.position or where.build_position)) end
  local project = {
    force_index = ctx.force_index, surface_index = ctx.surface_index, design_id = ctx.design_id, count = 0,
    rules = { charted_only = ctx.charted_only, generate = not ctx.charted_only and ctx.generate ~= false },
    gates = { materials = ctx.materials, reserve = 0 }, superforce = ctx.superforce,
  }
  return growth.try(project, { kind = "seed", position = position, direction = direction })
end

return growth
