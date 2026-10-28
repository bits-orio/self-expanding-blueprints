-- Q3 anchor stability: (i) a marker inside the bounds leaves every other ghost
-- where it was; (ii) clearing snapping on a snapped blueprint.
local fmt = require("lib.fmt")
local G = require("lib.geom")
local B = require("lib.bp")
local A = require("lib.analysis")
local D = require("lib.designs")
local Q = {id = "Q3"}

local DIRS = {0, 4, 8, 12}
local PS = {{x = 0, y = 0}, {x = 5, y = -3}, {x = -8, y = 11}}
local MARKER = "seb-spike-marker"

local function nauvis() return game.surfaces.nauvis end

-- Offsets of every ghost except markers, as a canonical string.
local function others_sig(rec)
  local keys = {}
  for _, g in pairs(rec.ghosts) do
    if g.name ~= MARKER then
      keys[#keys + 1] = (g.kind == "t" and "t:" or ("e" .. tostring(g.i) .. ":")) .. g.name .. "="
        .. fmt.p({x = g.pos.x - rec.P.x, y = g.pos.y - rec.P.y}) .. "/" .. g.dir
    end
  end
  table.sort(keys)
  return table.concat(keys, ";")
end

local function marker_ghost(rec)
  for _, g in pairs(rec.ghosts) do
    if g.name == MARKER then return g end
  end
end

local function covered(spec, x, y)
  for _, e in ipairs(spec.entities or {}) do
    local b = G.entity_box(e, "tile")
    if x + 0.5 > b.l and x + 0.5 < b.r and y + 0.5 > b.t and y + 0.5 < b.b then return true end
  end
  return false
end

-- Marker candidates: on an entity's tile, on an empty tile inside the bounds,
-- and just outside the bounds (expected to move things).
local function candidates(spec)
  local tb = G.bounds(spec.entities, spec.tiles, "tile")
  local out = {}
  local e1 = spec.entities[1]
  out[#out + 1] = {kind = "on-entity", pos = {x = math.floor(e1.position.x) + 0.5, y = math.floor(e1.position.y) + 0.5}}
  for x = tb.l, tb.r - 1 do
    for y = tb.t, tb.b - 1 do
      if not covered(spec, x, y) then
        out[#out + 1] = {kind = "empty-inside", pos = {x = x + 0.5, y = y + 0.5}}
        goto found
      end
    end
  end
  ::found::
  out[#out + 1] = {kind = "outside", pos = {x = tb.r + 0.5, y = tb.t + 0.5}}
  return out, tb
end

local function anchor_case(spec, cand, stats)
  local base = B.new(spec)
  local with = D.copy_spec(spec, spec.id .. "+m")
  with.entities[#with.entities + 1] = D.ent(MARKER, cand.pos.x, cand.pos.y, 4)
  local bpm = B.new(with)
  local same_all, details = true, {}
  for _, d in ipairs(DIRS) do
    for _, P in ipairs(PS) do
      local r0 = B.stamp(base, nauvis(), P, d)
      local r1 = B.stamp(bpm, nauvis(), P, d)
      local same = others_sig(r0) == others_sig(r1)
      local mg = marker_ghost(r1)
      local rig = A.rigid(bpm, r1)
      if not same then
        same_all = false
        local t0, t1 = A.rigid(base, r0).t, rig.t
        details[#details + 1] = "d" .. d .. "@" .. fmt.p(P) .. ":shift=" .. fmt.p(t0 and t1 and G.sub(t1, t0))
      end
      if not mg then details[#details + 1] = "d" .. d .. "@" .. fmt.p(P) .. ":NO-MARKER-GHOST" end
      if not rig.rigid then details[#details + 1] = "d" .. d .. "@" .. fmt.p(P) .. ":marker-not-rigid" end
    end
  end
  base.inv.destroy()
  bpm.inv.destroy()
  if cand.kind ~= "outside" then
    stats.n = stats.n + 1
    if not same_all then stats.fail = stats.fail + 1 end
  end
  return same_all, details
end

local function anchor_suite()
  local stats = {n = 0, fail = 0}
  for _, id in ipairs({"a", "b", "c", "c2", "g2"}) do
    local cands, tb = candidates(D[id])
    for _, cand in ipairs(cands) do
      local same, details = anchor_case(D[id], cand, stats)
      local ok = (cand.kind == "outside") or same
      fmt.verdict("Q3.anchor " .. id .. " " .. cand.kind .. "@" .. fmt.p(cand.pos), ok,
        "bounds_tile=" .. fmt.box(tb), "others_unchanged=" .. tostring(same), table.concat(details, " "))
    end
  end
  local specs = D.random(9001, 30)
  for _, spec in ipairs(specs) do
    if #spec.entities > 0 then
      local cands = candidates(spec)
      for _, cand in ipairs(cands) do
        if cand.kind ~= "outside" then anchor_case(spec, cand, stats) end
      end
    end
  end
  fmt.verdict("Q3.anchor.summary", stats.fail == 0, "inside_cases=" .. stats.n, "changed=" .. stats.fail)
end

-- (ii) snapping cleared on the same stack.
local function stored_positions(bp)
  local t = {}
  for i, e in pairs(bp.ents) do t[#t + 1] = i .. ":" .. fmt.p(e.position) end
  table.sort(t)
  return table.concat(t, " ")
end

local function snap_clear_case(id)
  local snapped = B.new(D[id])
  local plain = B.new(D.a)
  local before = stored_positions(snapped)
  local per_d = {}
  for _, d in ipairs(DIRS) do
    for _, P in ipairs(PS) do
      local rs = B.stamp(snapped, nauvis(), P, d)
      local rp = B.stamp(plain, nauvis(), P, d)
      local ts, tp = A.rigid(snapped, rs).t, A.rigid(plain, rp).t
      per_d[#per_d + 1] = "d" .. d .. "@" .. fmt.p(P) .. ":delta=" .. fmt.p(ts and tp and G.sub(ts, tp))
    end
  end
  snapped.stack.blueprint_snap_to_grid = nil
  snapped.stack.blueprint_absolute_snapping = false
  B.read(snapped)
  local after = stored_positions(snapped)
  local same_as_plain = true
  for _, d in ipairs(DIRS) do
    for _, P in ipairs(PS) do
      local rs = B.stamp(snapped, nauvis(), P, d)
      local rp = B.stamp(plain, nauvis(), P, d)
      if B.sig(rs) ~= B.sig(rp) then same_as_plain = false end
    end
  end
  fmt.verdict("Q3.snapclear " .. id, same_as_plain and before == after,
    "snapped_vs_unsnapped: " .. table.concat(per_d, " "),
    "| after_clear snap=" .. fmt.line(snapped.stack.blueprint_snap_to_grid),
    "abs=" .. tostring(snapped.stack.blueprint_absolute_snapping),
    "rel=" .. fmt.line(snapped.stack.blueprint_position_relative_to_grid),
    "stored_positions_unchanged=" .. tostring(before == after), "cleared_equals_unsnapped=" .. tostring(same_as_plain))
  snapped.inv.destroy()
  plain.inv.destroy()
end

function Q.run()
  anchor_suite()
  for _, id in ipairs({"e", "e2", "f", "f2", "f0"}) do snap_clear_case(id) end
end

return Q
