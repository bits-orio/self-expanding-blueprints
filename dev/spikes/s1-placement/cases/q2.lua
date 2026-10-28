-- Q2 rigid transform: ghost = t_d + R_d(blueprint position) for every entity,
-- and which placement model predicts t_d.
local fmt = require("lib.fmt")
local G = require("lib.geom")
local B = require("lib.bp")
local A = require("lib.analysis")
local D = require("lib.designs")
local Rng = require("lib.rng")
local Q = {id = "Q2"}

local DIRS = {0, 4, 8, 12}

local function nauvis() return game.surfaces.nauvis end

local function named_case(id)
  local bp = B.new(D[id])
  local tb = G.bounds(bp.ent_list, bp.tiles, "tile")
  local c = G.center(tb)
  for _, d in ipairs(DIRS) do
    for _, P in ipairs({{x = 0, y = 0}, {x = 5, y = -3}}) do
      local rec = B.stamp(bp, nauvis(), P, d)
      local r = A.rigid(bp, rec)
      local m = A.models(bp, P, d)
      fmt.verdict("Q2.rigid " .. id .. " d=" .. d .. " P=" .. fmt.p(P), r.rigid and r.missing == 0,
        "t=" .. fmt.p(r.t), "t-P=" .. fmt.p(r.t and G.sub(r.t, P)), "maxdev=" .. fmt.n(r.maxdev),
        "missing=" .. r.missing, "tiles_ok=" .. tostring(r.tiles_ok))
      local ok_round, ok_srb = A.match(r.t, m.round_tile), A.match(r.t, m.srb)
      fmt.verdict("Q2.model " .. id .. " d=" .. d .. " P=" .. fmt.p(P), ok_round and ok_srb,
        "bounds_tile=" .. fmt.box(tb), "c=" .. fmt.p(c), "R_d(c)=" .. fmt.p(G.rot(c, d)),
        "t_obs=" .. fmt.p(r.t), "t_round=" .. fmt.p(m.round_tile), "t_srb=" .. fmt.p(m.srb),
        "round_tile=" .. tostring(ok_round), "srb=" .. tostring(ok_srb),
        "round_coll=" .. tostring(A.match(r.t, m.round_coll)))
      fmt.verdict("Q2.dir " .. id .. " d=" .. d .. " P=" .. fmt.p(P), #r.dir_bad == 0,
        "exact=" .. r.dir_exact, "nonrotatable_stay_0=" .. r.dir_fixed,
        "opposite=" .. table.concat(r.dir_opposite, ","), "bad=" .. table.concat(r.dir_bad, ","))
    end
  end
  bp.inv.destroy()
end

local function new_stats()
  return {builds = 0, rigid_fail = 0, missing = 0, round_fail = 0, srb_fail = 0, srb_n = 0, coll_fail = 0,
    dir_bad = 0, dir_opposite = {}, fixups = 0, examples = 0, entities = 0, tiles = 0, missing_by = {}}
end

local function note_failure(st, spec, rec, r, m, why)
  if st.examples >= 6 then return end
  st.examples = st.examples + 1
  fmt.out("Q2.random.example", why, spec.id, "d=" .. rec.d, "P=" .. fmt.p(rec.P), "t_obs=" .. fmt.p(r.t),
    "t_round=" .. fmt.p(m.round_tile), "t_srb=" .. fmt.p(m.srb), "t_round_coll=" .. fmt.p(m.round_coll),
    "bounds_tile=" .. fmt.box(m.bounds_tile), "bounds_coll=" .. fmt.box(m.bounds_coll),
    "dir_bad=" .. table.concat(r.dir_bad, ","), "missing=" .. r.missing, "spec=" .. fmt.line(spec))
end

local function random_build(st, bp, spec, P, d, integer_p)
  local rec = B.stamp(bp, nauvis(), P, d)
  local r = A.rigid(bp, rec)
  local m = A.models(bp, P, d)
  st.builds = st.builds + 1
  if not r.rigid then st.rigid_fail = st.rigid_fail + 1 note_failure(st, spec, rec, r, m, "not-rigid") end
  if r.missing > 0 then
    st.missing = st.missing + 1
    for _, name in ipairs(r.missing_names) do st.missing_by[name] = (st.missing_by[name] or 0) + 1 end
  end
  if not A.match(r.t, m.round_tile) then st.round_fail = st.round_fail + 1 note_failure(st, spec, rec, r, m, "round") end
  if not A.match(r.t, m.round_coll) then st.coll_fail = st.coll_fail + 1 end
  if integer_p then
    st.srb_n = st.srb_n + 1
    if not A.match(r.t, m.srb) then st.srb_fail = st.srb_fail + 1 note_failure(st, spec, rec, r, m, "srb") end
  end
  if #r.dir_bad > 0 then st.dir_bad = st.dir_bad + 1 note_failure(st, spec, rec, r, m, "dir") end
  for _, o in ipairs(r.dir_opposite) do
    local name = o:match("^([^%(]+)")
    st.dir_opposite[name] = (st.dir_opposite[name] or 0) + 1
  end
end

local function random_sweep()
  local specs = D.random(4242, 80)
  local rng = Rng.new(777)
  local st = new_stats()
  for _, spec in ipairs(specs) do
    local bp = B.new(spec)
    st.fixups = st.fixups + #B.report_fixups(bp)
    st.entities = st.entities + #bp.ent_list
    st.tiles = st.tiles + #bp.tiles
    for _, d in ipairs(DIRS) do
      for _ = 1, 3 do
        random_build(st, bp, spec, {x = rng:int(-60, 60), y = rng:int(-60, 60)}, d, true)
      end
      for _ = 1, 2 do
        local P = {x = rng:int(-60, 60) + rng:int(0, 7) / 8, y = rng:int(-60, 60) + rng:int(0, 7) / 8}
        random_build(st, bp, spec, P, d, false)
      end
    end
    bp.inv.destroy()
  end
  local opp, miss = {}, {}
  for k, v in pairs(st.dir_opposite) do opp[#opp + 1] = k .. "=" .. v end
  for k, v in pairs(st.missing_by) do miss[#miss + 1] = k .. "=" .. v end
  table.sort(opp)
  table.sort(miss)
  fmt.out("Q2.random.missing_ghosts_by_entity", table.concat(miss, ","))
  fmt.verdict("Q2.random", st.rigid_fail == 0 and st.round_fail == 0 and st.srb_fail == 0
    and st.dir_bad == 0, "designs=" .. #specs, "entities=" .. st.entities, "tiles=" .. st.tiles,
    "builds=" .. st.builds, "rigid_fail=" .. st.rigid_fail, "missing_ghost_builds=" .. st.missing,
    "round_tile_fail=" .. st.round_fail, "srb_fail=" .. st.srb_fail .. "/" .. st.srb_n,
    "round_coll_fail=" .. st.coll_fail, "dir_bad_builds=" .. st.dir_bad,
    "dir_opposite_by_entity=" .. table.concat(opp, ","), "stored_position_fixups=" .. st.fixups)
end

local function pool_report()
  local parts = {}
  for _, entry in ipairs(D.POOL) do
    local p = prototypes.entity[entry[1]]
    parts[#parts + 1] = entry[1] .. "=" .. p.tile_width .. "x" .. p.tile_height .. (p.supports_direction and "r" or "")
  end
  fmt.out("Q2.pool", table.concat(parts, " "))
end

function Q.run()
  pool_report()
  for _, id in ipairs({"a", "a_shift", "b", "c", "c2", "g1", "g2", "g4", "q4"}) do named_case(id) end
  random_sweep()
end

return Q
