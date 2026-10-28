-- Q1 translation invariance: off(e) = ghost.position - P across many P.
local fmt = require("lib.fmt")
local G = require("lib.geom")
local B = require("lib.bp")
local A = require("lib.analysis")
local D = require("lib.designs")
local Q = {id = "Q1"}

local DIRS = {0, 4, 8, 12}
local INT_P = {
  {0, 0}, {1, 0}, {0, 1}, {1, 1}, {-1, -1}, {2, 3}, {-3, 2}, {7, -8}, {-12, -5}, {33, -17},
  {100, -37}, {-101, 64}, {2000, -3001}, {-99999, 100001},
}
local FRAC_P = {
  {0.5, 0.5}, {0.25, 0.25}, {0.75, 0.75}, {-0.5, -0.5}, {-0.25, -0.25}, {-0.75, -0.75},
  {0.5, 0}, {0, 0.5}, {1.5, -1.5}, {0.4, 0.6}, {-1.5, 2.5}, {0.125, 0.875},
}
local ORIGIN = {x = 0, y = 0}

local function P(t) return {x = t[1], y = t[2]} end
local function nauvis() return game.surfaces.nauvis end

-- Integer P: compare offset signatures with P = (0, 0).
local function check_integer(bp, d, plist, grid_label)
  local base = B.stamp(bp, nauvis(), ORIGIN, d)
  local sig0 = B.sig(base)
  storage.sig[bp.id .. "/" .. d] = sig0
  local bad, effs = {}, {}
  local min0 = B.min_pos(base)
  for _, p in ipairs(plist) do
    local rec = B.stamp(bp, nauvis(), P(p), d)
    if B.sig(rec) ~= sig0 then
      local eff = G.sub(B.min_pos(rec), min0)
      bad[#bad + 1] = fmt.p(P(p)) .. "->eff " .. fmt.p(eff)
    end
  end
  fmt.verdict("Q1.int " .. bp.id .. " d=" .. d, #bad == 0, "P_tested=" .. #plist,
    "n_ret=" .. base.n_ret .. "(e" .. base.ret_e .. "+t" .. base.ret_t .. ")", "n_found=" .. base.n_found,
    "expected=" .. B.expected_count(bp), grid_label or "",
    #bad > 0 and ("differs: " .. table.concat(bad, " ")) or "", "off0=" .. sig0)
  return base
end

-- Fractional P: the stamp must be a rigid integer translation of the P = 0 stamp.
local function check_fractional(bp, d, base, model_grid)
  local m = A.models(bp, ORIGIN, d)
  local min0 = B.min_pos(base)
  local abs0 = B.shifted_sig(base, ORIGIN)
  local rigid_all, model_all, list = true, true, {}
  for _, p in ipairs(FRAC_P) do
    local pp = P(p)
    local rec = B.stamp(bp, nauvis(), pp, d)
    local eff = G.sub(B.min_pos(rec), min0)
    local rigid = B.shifted_sig(rec, eff) == abs0
    rigid_all = rigid_all and rigid
    local item = fmt.p(pp) .. "->" .. fmt.p(eff) .. (rigid and "" or "(NOT-RIGID)")
    if model_grid and m.bounds_tile then
      local pred = G.sub(G.t_round(m.bounds_tile, pp, d, model_grid), G.t_round(m.bounds_tile, ORIGIN, d, model_grid))
      if not G.same(eff, pred) then
        model_all = false
        item = item .. "(model " .. fmt.p(pred) .. ")"
      end
    end
    list[#list + 1] = item
  end
  local rb = m.bounds_tile and G.rot_box(m.bounds_tile, d)
  local size = rb and (fmt.n(rb.r - rb.l) .. "x" .. fmt.n(rb.b - rb.t)) or "?"
  fmt.verdict("Q1.frac " .. bp.id .. " d=" .. d, rigid_all and (model_all or not model_grid),
    "rotated_tile_size=" .. size, "model=" .. (model_grid and ("round/grid" .. model_grid) or "n/a"),
    "P->eff: " .. table.concat(list, " "))
end

local function run_design(spec, opts)
  local bp = B.new(spec)
  local fix = B.report_fixups(bp)
  fmt.out("Q1.design " .. bp.id, "stored_entities=" .. #bp.ent_list, "stored_tiles=" .. #bp.tiles,
    "snap=" .. fmt.line(bp.stack.blueprint_snap_to_grid), "abs=" .. tostring(bp.stack.blueprint_absolute_snapping),
    "rel=" .. fmt.line(bp.stack.blueprint_position_relative_to_grid),
    "bounds_tile=" .. fmt.box(G.bounds(bp.ent_list, bp.tiles, "tile")),
    "bounds_coll=" .. fmt.box(G.bounds(bp.ent_list, bp.tiles, "coll")),
    "fixups=" .. fmt.line(fix))
  for _, d in ipairs(DIRS) do
    local base = check_integer(bp, d, (opts and opts.int_p) or INT_P, opts and opts.label)
    check_fractional(bp, d, base, opts and opts.model_grid)
  end
  return bp
end

-- Absolute snapping: sweep P along each axis and print the effective shift.
local function absolute_sweep(spec)
  local bp = B.new(spec)
  fmt.out("Q1.abs.design " .. bp.id, "snap=" .. fmt.line(bp.stack.blueprint_snap_to_grid),
    "abs=" .. tostring(bp.stack.blueprint_absolute_snapping),
    "rel=" .. fmt.line(bp.stack.blueprint_position_relative_to_grid),
    "stored=" .. fmt.line((function()
      local t = {}
      for i, e in pairs(bp.ents) do t[#t + 1] = i .. ":" .. fmt.p(e.position) end
      return t
    end)()))
  for _, d in ipairs(DIRS) do
    local base = B.stamp(bp, nauvis(), ORIGIN, d)
    local r0 = A.rigid(bp, base)
    local xs, ys, misses, n = {}, {}, {}, 0
    local function check(Pq, rec)
      local r = A.rigid(bp, rec)
      local pred = G.t_abs(Pq, d, spec.snap, spec.rel)
      n = n + 1
      if not (r.rigid and r.missing == 0 and A.match(r.t, pred)) then
        misses[#misses + 1] = fmt.p(Pq) .. ":t=" .. fmt.p(r.t) .. "/pred=" .. fmt.p(pred)
      end
      return r.t
    end
    for v = -7, 7 do
      local px, py = {x = v, y = 0}, {x = 0, y = v}
      local tx = check(px, B.stamp(bp, nauvis(), px, d))
      local ty = check(py, B.stamp(bp, nauvis(), py, d))
      xs[#xs + 1] = v .. ":" .. fmt.n(tx and tx.x)
      ys[#ys + 1] = v .. ":" .. fmt.n(ty and ty.y)
    end
    local fr = {}
    for _, p in ipairs({{0.5, 0.5}, {2.5, 1.5}, {-0.5, -0.5}, {5.75, 5.25}, {-13, 9}, {40.25, -33.75}}) do
      local t = check(P(p), B.stamp(bp, nauvis(), P(p), d))
      fr[#fr + 1] = fmt.p(P(p)) .. "->t" .. fmt.p(t)
    end
    fmt.verdict("Q1.abs " .. bp.id .. " d=" .. d, #misses == 0, "model=t_abs", "checked=" .. n,
      "t(P=0)=" .. fmt.p(r0.t), "Px->t.x: " .. table.concat(xs, " "), "| Py->t.y: " .. table.concat(ys, " "),
      "| more: " .. table.concat(fr, " "), #misses > 0 and ("| misses: " .. table.concat(misses, " ")) or "")
  end
  bp.inv.destroy()
end

-- Rails: capture real rails with create_blueprint so positions are canonical.
local RAIL_SPECS = {
  {id = "d1", list = {{"straight-rail", 1, 1, 0}}},
  {id = "d2", list = {{"straight-rail", 1, 1, 0}, {"straight-rail", 5, 5, 4}}},
  {id = "d3", list = {{"straight-rail", 1, 1, 0}, {"curved-rail-a", 9, 3, 0}, {"wooden-chest", -3.5, 0.5}}},
  {id = "d4", list = {{"curved-rail-a", 1, 2, 0}}},
  {id = "d5", list = {{"straight-rail", 1, 1, 0}, {"wooden-chest", 3.5, 0.5}}},
}

local function capture(spec)
  local s = nauvis()
  local o = {x = -140, y = -140}
  local made = {}
  for _, b in ipairs(spec.list) do
    local e = s.create_entity({name = b[1], position = {o.x + b[2], o.y + b[3]}, direction = b[4], force = "player"})
    if e then
      made[#made + 1] = e
      fmt.out("Q1.rail.src " .. spec.id, b[1], "asked=" .. fmt.p({x = o.x + b[2], y = o.y + b[3]}),
        "got=" .. fmt.p(e.position), "dir=" .. e.direction)
    else
      fmt.out("Q1.rail.src " .. spec.id, "CREATE-FAILED", b[1])
    end
  end
  local inv = game.create_inventory(1)
  inv[1].set_stack({name = "blueprint"})
  inv[1].create_blueprint({surface = s, force = "player", area = {{o.x - 16, o.y - 16}, {o.x + 16, o.y + 16}}})
  for _, e in pairs(made) do e.destroy() end
  local bp = B.wrap(spec.id, inv)
  for _, e in ipairs(bp.ent_list) do
    local proto = prototypes.entity[e.name]
    fmt.out("Q1.rail.bp " .. spec.id, e.name, "pos=" .. fmt.p(e.position), "dir=" .. (e.direction or 0),
      "tile=" .. proto.tile_width .. "x" .. proto.tile_height, "grid=" .. proto.build_grid_size)
  end
  return bp
end

local RAIL_P = {
  {0, 0}, {1, 0}, {0, 1}, {1, 1}, {2, 0}, {0, 2}, {2, 2}, {3, 3}, {-1, 0}, {0, -1}, {-1, -1}, {-2, -2},
  {-3, 5}, {4, -6}, {100, -37}, {-101, 64},
}

local function rail_case(spec)
  local bp = capture(spec)
  for _, d in ipairs(DIRS) do
    local base = B.stamp(bp, nauvis(), ORIGIN, d)
    storage.sig[bp.id .. "/" .. d] = B.sig(base)
    local min0 = B.min_pos(base)
    local abs0 = B.shifted_sig(base, ORIGIN)
    local m = A.models(bp, ORIGIN, d, 2)
    local list, rigid_all, even_inv, model_ok = {}, true, true, true
    local plist = {}
    for _, p in ipairs(RAIL_P) do plist[#plist + 1] = p end
    for _, p in ipairs(FRAC_P) do plist[#plist + 1] = p end
    for _, p in ipairs(plist) do
      local pp = P(p)
      local rec = B.stamp(bp, nauvis(), pp, d)
      local eff = G.sub(B.min_pos(rec), min0)
      local rigid = B.shifted_sig(rec, eff) == abs0
      rigid_all = rigid_all and rigid
      if pp.x % 2 == 0 and pp.y % 2 == 0 and not G.same(eff, pp) then even_inv = false end
      local pred = m.bounds_tile and G.sub(G.t_round(m.bounds_tile, pp, d, 2), G.t_round(m.bounds_tile, ORIGIN, d, 2))
      local ok = pred and G.same(pred, eff)
      model_ok = model_ok and ok
      list[#list + 1] = fmt.p(pp) .. "->" .. fmt.p(eff) .. (rigid and "" or "!") .. (ok and "" or "(m " .. fmt.p(pred) .. ")")
    end
    local r0 = A.rigid(bp, base)
    fmt.verdict("Q1.rail " .. bp.id .. " d=" .. d, rigid_all and even_inv,
      "n_found=" .. base.n_found, "expected=" .. B.expected_count(bp), "t(P=0)=" .. fmt.p(r0.t),
      "rigid_vs_R=" .. tostring(r0.rigid), "dir_bad=" .. table.concat(r0.dir_bad, ","),
      "dir_opposite=" .. table.concat(r0.dir_opposite, ","),
      "even_P_invariant=" .. tostring(even_inv), "model_round_grid2=" .. tostring(model_ok),
      "off0=" .. B.sig(base), "P->eff: " .. table.concat(list, " "))
  end
  storage.exports[bp.id] = bp.stack.export_stack()
  bp.inv.destroy()
end

-- Tile ghosts on a grass zone (lab tiles might behave differently).
local function grass_tiles()
  local bp = B.new(D.g2)
  local s = nauvis()
  for _, d in ipairs(DIRS) do
    local Pg = {x = 0, y = 400}
    local rec = B.stamp(bp, s, Pg, d)
    local ex = nil
    for _, g in pairs(rec.ghosts) do
      if g.kind == "t" then ex = g.name .. "@" .. fmt.p(g.pos) break end
    end
    local same = B.sig(rec) == storage.sig["g2/" .. d]
    fmt.verdict("Q1.tiles.grass g2 d=" .. d, same, "n_ret=" .. rec.n_ret .. "(e" .. rec.ret_e .. "+t" .. rec.ret_t .. ")",
      "n_found=" .. rec.n_found, "example_tile_ghost=" .. tostring(ex), "same_offsets_as_lab=" .. tostring(same))
  end
  bp.inv.destroy()
end

local function fog_cases()
  local bp = B.new(D.a)
  local s = nauvis()
  local r1 = B.stamp(bp, s, {x = 20, y = 20}, 0, {skip_fog = true})
  local r2 = B.stamp(bp, s, {x = 20, y = 20}, 0, {omit_skip_fog = true})
  fmt.out("Q1.fog uncharted skip_fog_of_war=true n_ret=" .. r1.n_ret .. " n_found=" .. r1.n_found,
    "| omitted n_ret=" .. r2.n_ret .. " n_found=" .. r2.n_found)
  -- charted but not currently visible (no radar, no player): fog of war proper
  game.forces.player.chart(s, {{-64, 32}, {-32, 64}})
  local P = {x = -48, y = 48}
  local charted = game.forces.player.is_chunk_charted(s, {x = -2, y = 1})
  local visible = game.forces.player.is_chunk_visible(s, {x = -2, y = 1})
  local r3 = B.stamp(bp, s, P, 0, {skip_fog = true})
  local r4 = B.stamp(bp, s, P, 0, {skip_fog = false})
  fmt.out("Q1.fog charted=" .. tostring(charted) .. " visible=" .. tostring(visible),
    "skip_fog_of_war=true n_ret=" .. r3.n_ret .. " | false n_ret=" .. r4.n_ret)
  bp.inv.destroy()
end

local function return_order()
  local bp = B.new(D.g3)
  local rec = B.stamp(bp, nauvis(), ORIGIN, 0)
  fmt.out("Q1.order g3 returned_order=" .. table.concat(rec.order, ","), "n_ret=" .. rec.n_ret)
  bp.inv.destroy()
  local bpa = B.new(D.c)
  local reca = B.stamp(bpa, nauvis(), ORIGIN, 4)
  fmt.out("Q1.order c returned_order=" .. table.concat(reca.order, ","))
  bpa.inv.destroy()
end

-- Runs from a later tick, after the chart request in fog_cases has had time.
function Q.fog_after_chart()
  local s = nauvis()
  local bp = B.new(D.a)
  local P = {x = -48, y = 48}
  local f = game.forces.player
  local charted = f.is_chunk_charted(s, {x = -2, y = 1})
  local visible = f.is_chunk_visible(s, {x = -2, y = 1})
  local r3 = B.stamp(bp, s, P, 0, {skip_fog = true})
  local r4 = B.stamp(bp, s, P, 0, {skip_fog = false})
  local r5 = B.stamp(bp, s, {x = 20, y = 20}, 0, {skip_fog = true})
  local r6 = B.stamp(bp, s, {x = 20, y = 20}, 0, {omit_skip_fog = true})
  fmt.out("Q1.fog tick=" .. game.tick, "charted=" .. tostring(charted), "visible=" .. tostring(visible),
    "skip_fog_of_war=true n_ret=" .. r3.n_ret, "| false n_ret=" .. r4.n_ret,
    "| uncharted chunk (0,0) skip_fog_of_war=true n_ret=" .. r5.n_ret, "| omitted n_ret=" .. r6.n_ret)
  bp.inv.destroy()
end

function Q.run()
  for _, id in ipairs({"a", "a_shift", "b", "c", "c2", "g1", "g2", "g3", "g4", "q4"}) do
    local bp = run_design(D[id], {model_grid = 1})
    bp.inv.destroy()
  end
  local bad = B.new(D.a_bad)
  fmt.out("Q1.fixups a_bad default fix_positions:", fmt.line(B.report_fixups(bad)))
  bad.inv.destroy()
  local bad2 = B.new(D.with(D.a_bad, "a_bad_nofix", {fix_positions = false}))
  fmt.out("Q1.fixups a_bad fix_positions=false:", fmt.line(B.report_fixups(bad2)))
  bad2.inv.destroy()
  for _, id in ipairs({"e", "e2", "e3"}) do
    local bp = run_design(D[id], {label = "relative-snap", model_grid = 1})
    bp.inv.destroy()
  end
  for _, id in ipairs({"f", "f2", "f0", "f3"}) do absolute_sweep(D[id]) end
  for _, spec in ipairs(RAIL_SPECS) do rail_case(spec) end
  grass_tiles()
  fog_cases()
  return_order()
end

return Q
