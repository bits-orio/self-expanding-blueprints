-- Find: the nearest spot within the Radius signal (at most 64 tiles) of
-- X, Y where a design fits, turned by Rotation: every check a stamp makes
-- there passes (rules, other copies, terrain, obstacles, probes), as a dry
-- run sees it. DONE with that spot in X and Y (relative to the builder
-- unless Absolute is set, like the request's own X and Y); ERR "not found".
-- Spots are tried ring by ring outward, a few dozen per read at most and
-- only while the team's share of server time allows (D44), each charged
-- for the work it did, however far it got (work.lua), so a wide search,
-- or one with a big or heavily probed design, runs over several seconds
-- instead of in one tick.

local placement = require("scripts.core.placement")
local growth = require("scripts.core.growth")
local budget = require("scripts.core.budget")
local work = require("scripts.core.work")
local answer = require("scripts.circuit.answer")
local design_of = require("scripts.circuit.verbs.design_of")
local library = require("scripts.core.library")
local limits = require("scripts.core.limits")

local find = {}

local DEFAULT_RADIUS = 16
local MAX_RADIUS = 64
local PER_READ = 40
local virtual = answer.virtual

-- The k-th tile of ring r (the square r tiles out), or nil past its end.
local function ring_tile(r, k)
  if r == 0 then return k == 0 and { 0, 0 } or nil end
  local side = 2 * r
  if k >= 4 * side then return nil end
  local edge, t = math.floor(k / side), k % side
  if edge == 0 then return { -r + t, -r } end
  if edge == 1 then return { r, -r + t } end
  if edge == 2 then return { r - t, r } end
  return { -r, r - t }
end

-- A project that plans and never stamps: growth.try says "planned" where
-- the design fits. Like every plan it never has the game make map (D43).
local function probe_project(b, design)
  local force_index = b.force_index
  return {
    force_index = force_index, surface_index = b.entity.surface_index, design_id = design.id,
    dry_run = true, planned = {}, plan_chunks = {}, count = 0,
    rules = { charted_only = limits.of(force_index, "builders_charted_only"), generate = false },
    gates = { materials = false, reserve = 0 },
  }
end

function find.start(b, request, input)
  local design = design_of(b, input)
  if not (design and design.prepared and design.prepared.ok) then return answer.fail(b, "unknown-design") end
  request.design_id = design.id
  request.center = answer.target(b, input)
  if not request.center then return answer.fail(b, "invalid") end
  request.radius = math.min(MAX_RADIUS, math.max(0, input.virtual["seb-radius"] or DEFAULT_RADIUS))
  request.direction = answer.direction(input)
  request.absolute = input.virtual["seb-absolute"] ~= nil
  request.ring, request.k = 0, 0
  find.tick(b, request)
end

-- Whether the design fits at the spot, and the spot. search: b, request,
-- prepared, probe.
local function fits(search, offset)
  local request, prepared = search.request, search.prepared
  local point = { x = request.center.x + offset[1], y = request.center.y + offset[2] }
  local position = placement.seed(prepared, { position = point }, request.direction)
  if not position then return false end
  local result = growth.try(search.probe, { kind = "seed", position = position, direction = request.direction })
  work.charge(search.b.force_index, result.work)
  return result.kind == "planned", point
end

local function report(b, request, point)
  local x, y = math.floor(point.x), math.floor(point.y)
  if not request.absolute then
    local p = b.entity.position
    x, y = x - math.floor(p.x), y - math.floor(p.y)
  end
  answer.done(b, { [virtual("signal-X")] = x, [virtual("signal-Y")] = y })
end

function find.tick(b, request)
  -- The force's library goes when its team is released or merged, while a
  -- search may still run.
  local design = library.get(b.force_index, request.design_id)
  if not (design and design.prepared and design.prepared.ok) then return answer.fail(b, "unknown-design") end
  local search = { b = b, request = request, prepared = design.prepared, probe = probe_project(b, design) }
  for _ = 1, PER_READ do
    if not budget.ready(b.force_index) then return end
    local offset = ring_tile(request.ring, request.k)
    if not offset then
      request.ring, request.k = request.ring + 1, 0
      if request.ring > request.radius then return answer.fail(b, "not-found") end
    else
      local ok, point = fits(search, offset)
      request.k = request.k + 1
      if ok then return report(b, request, point) end
    end
  end
end

return find
