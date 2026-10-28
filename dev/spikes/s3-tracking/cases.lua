-- The cases, one per question, and the hooks that judge them.
local lg = require("lg")
local bp = require("bp")
local track = require("track")
local sched = require("sched")
local rig = require("rig")
local C = {}

local hooks = track.hooks
local RED = defines.wire_connector_id.circuit_red

local function with_bp(design, fn)
  local entities, tiles = design()
  local inv, stack = bp.new(entities, tiles)
  local ok, a, b = pcall(fn, stack)
  inv.destroy()
  if not ok then error(a) end
  return a, b
end

local function by_x(list)
  table.sort(list, function(a, b) return a.position.x < b.position.x end)
  return list
end

local function entity_ghosts(ghosts)
  local list = {}
  for _, g in pairs(ghosts) do
    if g.valid and g.name == "entity-ghost" then list[#list + 1] = g end
  end
  return by_x(list)
end

local function done(name)
  storage.done[name] = true
end

local function window(name, fn)
  storage.window = name
  local s0 = storage.seq
  local ok, a, b, c = pcall(fn)
  storage.window = nil
  if not ok then error(a) end
  return storage.seq - s0, a, b, c
end

-- A: robot path (Q1, Q2, Q3) ---------------------------------------------------

function C.A(surface)
  storage.A = with_bp(bp.A, function(s)
    return track.stamp("A", s, surface, {10, -15}, {verbose = true})
  end).id
end

hooks.A = function(inst)
  local kept = false
  for unit, tags in pairs(inst.tags_seen) do
    if tags.design_tag == "kept" and tags.seb_instance == inst.id then kept = true end
  end
  lg.verdict("Q1", "robot_built_carries_tags", inst.built_tagged == inst.n_ghosts and (inst.paths.robot or 0) == inst.n_ghosts,
    string.format("robot_built=%d tagged=%d ghosts=%d", inst.paths.robot or 0, inst.built_tagged, inst.n_ghosts))
  lg.verdict("Q1", "blueprint_tag_survives_merge", kept, "iron-chest tags=" .. lg.ser(inst.tags_seen))
  local same = 0
  for unit in pairs(inst.entities) do if inst.ghost_by_unit[unit] then same = same + 1 end end
  lg.answer("Q2", "robot_built_entity_keeps_ghost_unit_number", same == inst.n_ghosts,
    string.format("same=%d of %d ghost_unit_number_nonnil=%d", same, inst.n_ghosts, inst.ghost_unit_number_nonnil))
  sched.at(game.tick + 30, "A_destroy_one", inst.id)
end

sched.tasks.A_destroy_one = function(id)
  local inst = storage.inst[id]
  for unit, e in pairs(inst.entity_refs) do
    if e.valid and e.name == "small-lamp" then
      storage.A_destroyed_unit = unit
      storage.A_destroy_tick = game.tick
      local n, ok = window("A:entity.destroy", function() return e.destroy() end)
      lg.out("A_DESTROY_BUILT unit=" .. unit .. " destroy_returned=" .. tostring(ok) .. " lines_in_window=" .. n)
      return
    end
  end
end

hooks["A:destroyed"] = function(inst, r, e)
  if r.unit ~= storage.A_destroyed_unit then return end
  lg.verdict("Q3", "built_entity_registration_fires_on_destroy", e.useful_id == r.unit,
    string.format("unit=%s useful_id=%s ticks_after_destroy_call=%d", tostring(r.unit), tostring(e.useful_id),
      game.tick - (storage.A_destroy_tick or game.tick)))
  lg.out(string.format("A_STATS delta_hist=%s order_bad=%d useful_eq_ghost_unit=%d ghost_unit_number_nonnil=%d",
    lg.ser(inst.delta_hist), inst.order_bad, inst.useful_eq_unit, inst.ghost_unit_number_nonnil))
  sched.at(game.tick + 30, "A_die_one", inst.id)
end

-- Extra probe E1: an instance entity dies and the force rebuilds it from a
-- death ghost. Does that ghost (or the rebuilt entity's event) carry the tag?
sched.tasks.A_die_one = function(id)
  local inst = storage.inst[id]
  game.forces.player.create_ghost_on_entity_death = true
  for unit, e in pairs(inst.entity_refs) do
    if e.valid and e.name == "wooden-chest" then
      local surface, pos = e.surface, e.position
      local n = window("E1:entity.die", function() return e.die() end)
      local ghosts = surface.find_entities_filtered{position = pos, type = "entity-ghost"}
      local g = ghosts[1]
      storage.E1 = {unit = unit, pos = pos, tick = game.tick}
      lg.out(string.format("E1 died unit=%d lines_in_window=%d death_ghost=%s ghost_unit_number=%s tags=%s",
        unit, n, lg.ent(g), tostring(g and g.ghost_unit_number), lg.ser(g and g.tags)))
      if not g then done("A") end
      return
    end
  end
end

hooks.E1_rebuilt = function(ent, tags, path)
  lg.answer("E1", "death_ghost_rebuild_carries_seb_tag", tags ~= nil and tags.seb_instance ~= nil,
    string.format("path=%s ent=%s tags=%s ticks_after_death=%d", path, lg.ent(ent), lg.ser(tags),
      game.tick - storage.E1.tick))
  done("A")
end

-- S: script revive (Q1, Q2, Q5) -------------------------------------------------

local REVIVE_PLAN = {
  {"revive", true}, {"silent_revive", true}, {"revive", false}, {"revive", true}, {"silent_revive", false},
}

function C.S(surface)
  local inst, ghosts = with_bp(bp.S, function(s)
    return track.stamp("S", s, surface, {10, -25}, {verbose = true})
  end)
  storage.S = inst.id
  for i, g in ipairs(entity_ghosts(ghosts)) do
    local method, raise = REVIVE_PLAN[i][1], REVIVE_PLAN[i][2]
    local gunit, gtags, gdesc = g.unit_number, g.tags, lg.ent(g)
    local n, collided, ent, proxy = window("S:" .. method .. ":raise=" .. tostring(raise), function()
      return g[method]{raise_revive = raise}
    end)
    lg.out(string.format("REVIVE method=%s raise_revive=%s ghost=%s ghost_tags=%s collided=%s entity=%s"
      .. " entity_keeps_ghost_unit=%s proxy=%s proxy_target_is_entity=%s proxy_requests=%s ghost_valid_after=%s"
      .. " lines_in_window=%d",
      method, tostring(raise), gdesc, lg.ser(gtags), lg.ser(collided), lg.ent(ent),
      tostring(ent and ent.unit_number == gunit), lg.ent(proxy),
      tostring(proxy and proxy.proxy_target == ent), lg.ser(proxy and proxy.item_requests),
      tostring(g.valid), n))
    if ent and not raise then
      -- No event: the mod would have to record its own revives.
      track.on_entity_built(inst, ent, "script_revive_noraise", gtags)
    end
    if proxy then
      local preg = script.register_on_object_destroyed(proxy)
      if not storage.regs[preg] then
        storage.regs[preg] = {inst = inst.id, kind = "proxy", unit = proxy.unit_number,
          target = ent.unit_number, built_tick = game.tick}
        lg.out("S proxy registered after revive returned (handler did not see it) preg=" .. preg)
      else
        lg.out("S proxy already registered by the revive handler preg=" .. preg)
      end
    end
  end
end

hooks.S = function(inst)
  local seen = {}
  for unit, tags in pairs(inst.tags_seen) do seen[#seen + 1] = unit .. ":" .. lg.ser(tags) end
  table.sort(seen)
  lg.verdict("Q1", "script_revive_raises_with_tags", (inst.paths.script_revive or 0) == 3,
    string.format("script_raised_revive_events=%d (expected 3: revive+raise, silent_revive+raise, AM2 revive+raise)"
      .. " noraise_manual=%d tags_seen=%s", inst.paths.script_revive or 0,
      inst.paths.script_revive_noraise or 0, table.concat(seen, " ")))
  lg.verdict("Q5", "revived_proxy_delivered", inst.proxy_delivered_tick ~= nil,
    "delivered_tick=" .. tostring(inst.proxy_delivered_tick))
  done("S")
end

-- T: tile ghosts (Q4) -----------------------------------------------------------

function C.T(surface)
  storage.T1 = with_bp(bp.T1, function(s)
    return track.stamp("T1", s, surface, {20, -15}, {verbose = true, tile_search = 4})
  end).id
  storage.T2 = with_bp(bp.T2, function(s)
    return track.stamp("T2", s, surface, {27, -15}, {verbose = true, tile_search = 3})
  end).id
end

local function tile_hook(inst)
  local surface = game.surfaces[inst.surface_index]
  local placed = 0
  for k in pairs(inst.tile_keys) do
    local x, y = k:match("^(-?%d+),(-?%d+)$")
    local t = surface.get_tile(tonumber(x), tonumber(y))
    if t.name == "stone-path" or t.name == "concrete" then placed = placed + 1 end
  end
  lg.verdict("Q4", inst.case .. "_tiles_built_and_events", placed == inst.n_tiles and inst.tiles_built == inst.n_tiles,
    string.format("n_tiles=%d placed=%d on_robot_built_tile_positions=%d tile_ghost_destroyed_events=%d"
      .. " delta_hist=%s", inst.n_tiles, placed, inst.tiles_built, inst.tile_ghosts_gone,
      lg.ser(inst.tile_delta_hist)))
  done(inst.case)
end
hooks.T1 = tile_hook
hooks.T2 = function(inst)
  tile_hook(inst)
  lg.verdict("Q4", "T2_entity_on_tiles_tagged", inst.built_tagged == inst.n_ghosts,
    string.format("built_tagged=%d n_ghosts=%d", inst.built_tagged, inst.n_ghosts))
end

-- M: item request proxies (Q5) ----------------------------------------------------

function C.M(surface)
  local inst = with_bp(bp.M, function(s)
    return track.stamp("M", s, surface, {-20, -15}, {verbose = true})
  end)
  storage.M = inst.id
  local proxies = surface.find_entities_filtered{area = inst.area, type = "item-request-proxy"}
  lg.out("M item_request_proxies_at_stamp=" .. #proxies)
end

-- M2: the same assembler stamped once the network is idle, for a clean
-- build-to-delivery time.
sched.tasks.M2 = function()
  local surface = game.surfaces.nauvis
  storage.M2 = with_bp(bp.M, function(s)
    return track.stamp("M2", s, surface, {-30, -15}, {verbose = true})
  end).id
end

hooks.M2 = function(inst)
  lg.answer("Q5", "idle_network_build_to_delivery_ticks",
    inst.proxy_delivered_tick and inst.built_tick and (inst.proxy_delivered_tick - (next(inst.built_tick) and
      inst.built_tick[next(inst.built_tick)])) or "nil",
    "stamp_to_complete=" .. tostring(inst.complete_tick - inst.created_tick))
  done("M2")
end

hooks.M = function(inst)
  local am
  for _, e in pairs(inst.entity_refs) do if e.valid then am = e end end
  local modules = am and am.get_module_inventory().get_contents()
  lg.verdict("Q5", "robot_built_proxy_delivered_then_complete", inst.proxy_delivered_tick ~= nil,
    "modules=" .. lg.ser(modules) .. " delivered_tick=" .. tostring(inst.proxy_delivered_tick)
    .. " complete_tick=" .. tostring(inst.complete_tick))
  done("M")
end

-- V: ghosts that vanish unbuilt (Q6) ------------------------------------------------

function C.V(surface)
  local inst, ghosts = with_bp(bp.V, function(s)
    return track.stamp("V", s, surface, {-20, -25}, {verbose = true})
  end)
  storage.V = inst.id
  local g = entity_ghosts(ghosts)
  local force = game.forces.player
  local n1, r1 = window("V:ghost.order_deconstruction", function() return g[1].order_deconstruction(force) end)
  lg.out("V order_deconstruction returned=" .. tostring(r1) .. " ghost_valid_after=" .. tostring(g[1].valid)
    .. " lines=" .. n1)
  local n2, r2 = window("V:ghost.destroy", function() return g[2].destroy() end)
  lg.out("V destroy returned=" .. tostring(r2) .. " lines=" .. n2)
  local n3, r3 = window("V:ghost.destroy_raise", function() return g[3].destroy{raise_destroy = true} end)
  lg.out("V destroy{raise_destroy} returned=" .. tostring(r3) .. " lines=" .. n3)
end

hooks.V = function(inst)
  lg.verdict("Q6", "vanished_ghosts_have_no_built_event", inst.vanished == 3 and inst.built == 1,
    string.format("ghosts=%d vanished=%d built=%d ghosts_gone=%d", inst.n_ghosts, inst.vanished,
      inst.built, inst.ghosts_gone))
  done("V")
end

-- R: forced mode over trees (Q7) ------------------------------------------------------

function C.R(surface)
  local pos = {-20, 15}
  local inv, s = bp.new(bp.R())
  local dry = s.build_blueprint{surface = surface, force = "player", position = pos,
    build_mode = defines.build_mode.normal, raise_built = false}
  local spots = {}
  for _, g in pairs(dry) do
    spots[#spots + 1] = {x = g.position.x, y = g.position.y}
    g.destroy()
  end
  table.sort(spots, function(a, b) return a.x < b.x end)
  local trees = {}
  for _, p in pairs(spots) do
    trees[#trees + 1] = surface.create_entity{name = "tree-01", position = p}
  end
  local last = spots[#spots]
  local control = surface.create_entity{name = "tree-01", position = {last.x + 3, last.y}}
  storage.R_trees, storage.R_control = trees, control
  local inst, ghosts = track.stamp("R", s, surface, pos, {verbose = true})
  inv.destroy()
  storage.R = inst.id
  for i, t in pairs(trees) do
    lg.out(string.format("R tree %d %s to_be_deconstructed=%s", i, lg.ent(t), tostring(t.valid and t.to_be_deconstructed())))
  end
  local _, err = lg.unit(control)
  lg.out("R reading tree.unit_number error=" .. tostring(err))
  lg.out(string.format("R control_tree %s to_be_deconstructed=%s ghosts_returned=%d", lg.ent(control),
    tostring(control.to_be_deconstructed()), #ghosts))
end

hooks.R = function(inst)
  local trees_gone = 0
  for _, t in pairs(storage.R_trees) do if not t.valid then trees_gone = trees_gone + 1 end end
  local control = storage.R_control
  lg.verdict("Q7", "forced_over_trees", trees_gone == #storage.R_trees and inst.built_tagged == inst.n_ghosts
    and control.valid and not control.to_be_deconstructed(),
    string.format("trees_gone=%d/%d built_tagged=%d/%d control_tree_valid=%s", trees_gone, #storage.R_trees,
      inst.built_tagged, inst.n_ghosts, tostring(control.valid)))
  done("R")
end

-- W: wires (Q9) ----------------------------------------------------------------

local function red_links(e)
  local c = e.get_wire_connector(RED, false)
  if not c then return "no-connector" end
  local out = {}
  for _, conn in pairs(c.connections) do
    out[#out + 1] = lg.ent(conn.target.owner) .. ":" .. tostring(conn.target.wire_connector_id)
  end
  return c.connection_count .. "/real=" .. c.real_connection_count .. "[" .. table.concat(out, ",") .. "]"
end

function C.W(surface)
  local inst, ghosts = with_bp(bp.W, function(s)
    local back = s.get_blueprint_entities()
    lg.out("W blueprint_wires_readback=" .. lg.ser(back and back[1] and back[1].wires))
    return track.stamp("W", s, surface, {-10, 25}, {verbose = true})
  end)
  storage.W = inst.id
  for _, g in pairs(entity_ghosts(ghosts)) do
    lg.out("W ghost " .. lg.ent(g) .. " red=" .. red_links(g))
  end
end

hooks.W = function(inst)
  local list, linked = {}, 0
  for _, e in pairs(inst.entity_refs) do
    if e.valid then
      list[#list + 1] = lg.ent(e) .. " red=" .. red_links(e)
      local c = e.get_wire_connector(RED, false)
      if c and c.real_connection_count == 1 then linked = linked + 1 end
    end
  end
  lg.verdict("Q9", "red_wire_survives_robot_build", linked == 2, table.concat(list, " | "))
  done("W")
end

-- C: recount at scale (Q8) and retirement at scale (Q10) ---------------------------

local function profile(inst, surface)
  local N = 100
  local fi = inst.force_index
  local p = helpers.create_profiler()
  local function run(label, fn)
    local r1, r2
    p.reset()
    for _ = 1, N do r1, r2 = fn() end
    p.stop()
    p.divide(N)
    lg.cost("Q8 cost " .. label .. " result=" .. tostring(r1) .. "/" .. tostring(r2) .. " avg_of_" .. N, p)
  end
  run("entity_ghosts find+tag_filter", function() return track.count_ghosts(inst, surface) end)
  run("entity_ghosts find_only", function()
    return #surface.find_entities_filtered{area = inst.area, type = "entity-ghost", force = fi}
  end)
  run("entity_ghosts count_only", function()
    return surface.count_entities_filtered{area = inst.area, type = "entity-ghost", force = fi}
  end)
  run("tile_ghosts find+key_filter", function() return track.count_tile_ghosts(inst, surface) end)
  run("tile_ghosts find+unit_filter", function() return track.count_tile_ghosts_by_unit(inst, surface) end)
  run("tile_ghosts stored_refs_valid_scan", function()
    local n = 0
    for _, g in pairs(inst.tile_refs) do if g.valid then n = n + 1 end end
    return n
  end)
  run("tile_ghosts count_only", function()
    return surface.count_entities_filtered{area = inst.area, name = "tile-ghost", force = fi}
  end)
  run("proxies find+target_filter", function() return track.count_proxies(inst, surface) end)
  run("full_recount", function() local g, t, pp = track.recount(inst); return g + t + pp end)
  run("stored_refs_valid_scan", function()
    local n = 0
    for _, g in pairs(inst.ghost_refs) do if g.valid then n = n + 1 end end
    return n
  end)
end

function C.C(surface)
  local inst = with_bp(bp.C, function(s)
    return track.stamp("C", s, surface, {25, 15}, {verbose = false})
  end)
  storage.C = inst.id
  profile(inst, surface)
end

-- While C builds: recount against the event-derived expectation.
function C.watch_C()
  local inst = storage.C and storage.inst[storage.C]
  if not inst or inst.state ~= "building" then return end
  local g, t, p = track.recount(inst)
  local eg = inst.n_ghosts - inst.built_tagged
  local et = inst.n_tiles - inst.tiles_built
  lg.out(string.format("C_RECOUNT ghosts=%d expect=%d tile_ghosts=%d expect=%d proxies=%d match=%s",
    g, eg, t, et, p, tostring(g == eg and t == et)))
  storage.C_mismatch = (storage.C_mismatch or 0) + ((g == eg and t == et) and 0 or 1)
  storage.C_samples = (storage.C_samples or 0) + 1
end

hooks.C = function(inst)
  lg.out(string.format("C_STATS same_unit=%s ghost_valid_in_handler=%s ghost_delta_hist=%s order_bad=%d"
    .. " tile_delta_hist=%s useful_eq_ghost_unit=%s ghost_unit_number_nonnil=%s paths=%s",
    tostring(inst.same_unit), tostring(inst.ghost_valid_in_handler), lg.ser(inst.delta_hist), inst.order_bad,
    lg.ser(inst.tile_delta_hist), tostring(inst.useful_eq_unit), tostring(inst.ghost_unit_number_nonnil),
    lg.ser(inst.paths)))
  lg.verdict("Q8", "recount_matches_events_while_building", (storage.C_mismatch or 0) == 0,
    string.format("samples=%d mismatches=%d", storage.C_samples or 0, storage.C_mismatch or 0))
  lg.verdict("Q1", "C_all_robot_builds_tagged", inst.built_tagged == inst.n_ghosts,
    string.format("built_tagged=%d n_ghosts=%d untagged_events=%s", inst.built_tagged, inst.n_ghosts,
      lg.ser(storage.untagged)))
  lg.verdict("Q3", "C_ghost_destroyed_after_built", inst.order_bad == 0 and inst.vanished == 0,
    string.format("delta_hist=%s order_bad=%d vanished=%d", lg.ser(inst.delta_hist), inst.order_bad, inst.vanished))
  sched.at(game.tick + 30, "retire", inst.id)
end

sched.tasks.retire = function(id) track.retire(storage.inst[id]) end

function C.watch_retiring()
  for _, inst in pairs(storage.inst) do
    if inst.state == "retiring" and not inst.verbose then
      local left = 0
      for _, e in pairs(inst.entity_refs) do if e.valid then left = left + 1 end end
      lg.out(string.format("RETIRING case=%s entities_left=%d entities_gone_events=%d tiles_mined=%d",
        inst.case, left, inst.entities_gone, inst.tiles_mined))
    end
  end
end

hooks["C:retired"] = function(inst)
  local surface = game.surfaces[inst.surface_index]
  local stone = 0
  for k in pairs(inst.tile_keys) do
    local x, y = k:match("^(-?%d+),(-?%d+)$")
    if surface.get_tile(tonumber(x), tonumber(y)).name == "stone-path" then stone = stone + 1 end
  end
  lg.verdict("Q10", "C_retired_fully", inst.entities_gone == inst.retire_entities and stone == 0,
    string.format("entity_destroyed_events=%d/%d tiles_still_stone=%d tiles_mined_events=%d after_ticks=%d",
      inst.entities_gone, inst.retire_entities, stone, inst.tiles_mined, game.tick - inst.retire_tick))
  done("C")
end

-- D: exact retirement next to neighbours (Q10) ---------------------------------------

function C.D(surface)
  local base = {42, -6}
  local inst, ghosts = with_bp(bp.D, function(s)
    return track.stamp("D", s, surface, base, {verbose = true})
  end)
  storage.D = inst.id
  local xs, cy = {}, nil
  for _, g in pairs(entity_ghosts(ghosts)) do
    xs[#xs + 1] = g.position.x
    cy = g.position.y
  end
  local tx0, ty = math.floor(xs[1]) - 1, math.floor(cy)
  local n_tiles = {{tx0, ty}, {tx0, ty + 1}}
  for x = math.floor(xs[1]), math.floor(xs[#xs]) do n_tiles[#n_tiles + 1] = {x, ty + 2} end
  local set = {}
  for _, p in pairs(n_tiles) do set[#set + 1] = {name = "stone-path", position = p} end
  surface.set_tiles(set, false, false, false, false)
  local n1 = rig.create(surface, {name = "iron-chest", position = {xs[#xs] + 1, cy}})
  local n2 = rig.create(surface, {name = "iron-chest", position = {xs[1] - 1, cy}})
  storage.D_neighbors = {entities = {n1, n2}, tiles = n_tiles}
  lg.out("D neighbours " .. lg.ent(n1) .. " " .. lg.ent(n2) .. " tiles=" .. lg.ser(n_tiles))
  storage.D2 = with_bp(bp.D, function(s)
    return track.stamp("D2", s, surface, {base[1], base[2] + 3}, {verbose = true})
  end).id
end

local function d_ready()
  local d, d2 = storage.inst[storage.D], storage.inst[storage.D2]
  if d.state == "complete" and d2.state == "complete" then
    sched.at(game.tick + 30, "retire", d.id)
  end
end
hooks.D = d_ready
hooks.D2 = d_ready

hooks["D:retired"] = function(inst)
  local surface = game.surfaces[inst.surface_index]
  local d_tiles_left = 0
  for k in pairs(inst.tile_keys) do
    local x, y = k:match("^(-?%d+),(-?%d+)$")
    if surface.get_tile(tonumber(x), tonumber(y)).name == "stone-path" then d_tiles_left = d_tiles_left + 1 end
  end
  local n_ok = 0
  for _, e in pairs(storage.D_neighbors.entities) do if e.valid then n_ok = n_ok + 1 end end
  local nt_ok = 0
  for _, p in pairs(storage.D_neighbors.tiles) do
    if surface.get_tile(p[1], p[2]).name == "stone-path" then nt_ok = nt_ok + 1 end
  end
  local d2 = storage.inst[storage.D2]
  local d2_ok = 0
  for _, e in pairs(d2.entity_refs) do if e.valid then d2_ok = d2_ok + 1 end end
  local d2_tiles = 0
  for k in pairs(d2.tile_keys) do
    local x, y = k:match("^(-?%d+),(-?%d+)$")
    if surface.get_tile(tonumber(x), tonumber(y)).name == "stone-path" then d2_tiles = d2_tiles + 1 end
  end
  local sample = next(inst.tile_keys)
  local sx, sy = sample:match("^(-?%d+),(-?%d+)$")
  local st = surface.get_tile(tonumber(sx), tonumber(sy))
  lg.verdict("Q10", "D_exact_retirement", d_tiles_left == 0 and n_ok == 2 and nt_ok == #storage.D_neighbors.tiles
    and d2_ok == 3 and d2_tiles == d2.n_tiles,
    string.format("d_entities_gone=%d/%d d_tiles_left=%d tile_now=%s neighbours_alive=%d/2 neighbour_tiles=%d/%d"
      .. " d2_entities=%d/3 d2_tiles=%d/%d after_ticks=%d", inst.entities_gone, inst.retire_entities,
      d_tiles_left, st.name, n_ok, nt_ok, #storage.D_neighbors.tiles, d2_ok, d2_tiles, d2.n_tiles,
      game.tick - inst.retire_tick))
  done("D")
end

-- P: space platform (Q11) ------------------------------------------------------------

function C.platform_setup()
  local force = game.forces.player
  local platform = force.create_space_platform{name = "seb-s3", planet = "nauvis",
    starter_pack = "space-platform-starter-pack"}
  if not platform then
    lg.out("P create_space_platform returned nil")
    return
  end
  local hub = platform.apply_starter_pack()
  if not hub then
    lg.out("P apply_starter_pack returned nil")
    return
  end
  local n1 = hub.insert{name = "iron-chest", count = 10}
  local n2 = hub.insert{name = "space-platform-foundation", count = 50}
  storage.platform_surface = platform.surface.index
  storage.platform_hub = hub
  lg.out(string.format("P platform=%s surface=%d hub=%s state=%s inserted chest=%d foundation=%d",
    platform.name, platform.surface.index, lg.ent(hub), tostring(platform.state), n1, n2))
end

local platform_answer

-- Platform variants: P1 forced extension (foundation + chest over empty space),
-- P2 the same superforced, P5 the same in normal mode, P3 a chest stamped on
-- existing foundation, P4 a chest stamped on P1's foundation once it is built.
local function charted(surface, x, y)
  return game.forces.player.is_chunk_charted(surface, {math.floor(x / 32), math.floor(y / 32)})
end

-- Before charting: a chest onto existing foundation (P0), then chart.
function C.P_uncharted()
  if not storage.platform_surface then return end
  local surface = game.surfaces[storage.platform_surface]
  lg.out("P charted_before platform_chunk_0_0=" .. tostring(charted(surface, 0, 0))
    .. " nauvis_chunk_of_A=" .. tostring(charted(game.surfaces.nauvis, 10, -15)))
  storage.P0 = with_bp(bp.chest, function(s)
    return track.stamp("P0", s, surface, {4.5, 4.5}, {verbose = true})
  end).id
  game.forces.player.chart(surface, {{-32, -32}, {31, 31}})
  sched.at(game.tick + 115, "P_main")
  sched.at(game.tick + 2, "P_debug")
end
sched.tasks.P_main = function() C.P() end

sched.tasks.P_poll_chart = function()
  local surface = game.surfaces[storage.platform_surface]
  local c = game.forces.player.is_chunk_charted(surface, {0, 0})
  local ok = surface.can_place_entity{name = "entity-ghost", inner_name = "iron-chest", position = {4.5, 4.5},
    force = "player", build_check_type = defines.build_check_type.blueprint_ghost}
  lg.out("PDBG poll platform_chunk_charted=" .. tostring(c) .. " blueprint_ghost_ok=" .. tostring(ok))
  if not c and game.tick < 1500 then sched.at(game.tick + 120, "P_poll_chart") end
end

-- Why do entity ghosts never land on the platform? Probe placement directly.
sched.tasks.P_debug = function()
  local surface = game.surfaces[storage.platform_surface]
  local pos = {4.5, 4.5}
  local t = surface.get_tile(4, 4)
  lg.out(string.format("PDBG tile(4,4)=%s chunk_generated=%s hub=%s", t.name,
    tostring(surface.is_chunk_generated({0, 0})), lg.ent(storage.platform_hub)))
  for name, v in pairs(defines.build_check_type) do
    local ok1 = surface.can_place_entity{name = "iron-chest", position = pos, force = "player", build_check_type = v}
    local ok2 = surface.can_place_entity{name = "entity-ghost", inner_name = "iron-chest", position = pos,
      force = "player", build_check_type = v}
    lg.out(string.format("PDBG can_place check=%s real=%s ghost=%s", name, tostring(ok1), tostring(ok2)))
  end
  local g = surface.create_entity{name = "entity-ghost", inner_name = "iron-chest", position = pos, force = "player"}
  lg.out("PDBG create_entity ghost -> " .. lg.ent(g))
  if g then g.destroy() end
  local chests = surface.find_entities_filtered{name = "iron-chest"}
  local hub_chests = storage.platform_hub.get_inventory(defines.inventory.hub_main).get_item_count("iron-chest")
  lg.out("PDBG platform iron-chest entities=" .. #chests .. " hub_iron_chests=" .. hub_chests)
  for _, c in pairs({{0, 0}, {0, -1}, {-1, -1}, {1, 1}, {3, 3}}) do
    lg.out(string.format("PDBG nauvis chunk %d,%d charted=%s", c[1], c[2],
      tostring(game.forces.player.is_chunk_charted(game.surfaces.nauvis, c))))
  end
  sched.at(game.tick + 60, "P_poll_chart")
  local BG = defines.build_check_type.blueprint_ghost
  local function bg(surf, name, at)
    return surf.can_place_entity{name = "entity-ghost", inner_name = name, position = at, force = "player",
      build_check_type = BG}
  end
  for _, name in pairs({"iron-chest", "small-lamp", "transport-belt", "inserter", "solar-panel", "cargo-bay"}) do
    local ok, res = pcall(bg, surface, name, {4.5, 4.5})
    lg.out("PDBG platform blueprint_ghost " .. name .. "=" .. (ok and tostring(res) or ("error " .. tostring(res))))
  end
  local states = {}
  for k, v in pairs(defines.space_platform_state) do states[v] = k end
  local platform = game.forces.player.platforms[next(game.forces.player.platforms)]
  lg.out("PDBG platform state=" .. tostring(states[platform.state]) .. " space_platforms_unlocked="
    .. tostring(game.forces.player.is_space_platforms_unlocked()) .. " built_platforms_at_nauvis="
    .. #game.forces.player.get_space_platforms("nauvis"))
  game.forces.player.unlock_space_platforms()
  lg.out("PDBG after unlock_space_platforms blueprint_ghost iron-chest=" .. tostring(bg(surface, "iron-chest", {4.5, 4.5})))
  local probe = game.create_surface("seb-probe")
  probe.request_to_generate_chunks({0, 0}, 1)
  probe.force_generate_chunk_requests()
  local tiles = {}
  for x = -3, 3 do for y = -3, 3 do tiles[#tiles + 1] = {name = "lab-dark-1", position = {x, y}} end end
  probe.set_tiles(tiles)
  lg.out("PDBG new_surface blueprint_ghost iron-chest=" .. tostring(bg(probe, "iron-chest", {0.5, 0.5}))
    .. " charted=" .. tostring(game.forces.player.is_chunk_charted(probe, {0, 0})))
  game.forces.player.chart_all(probe)
  lg.out("PDBG new_surface after chart_all charted=" .. tostring(game.forces.player.is_chunk_charted(probe, {0, 0})))
  local n = game.surfaces.nauvis
  for _, d in pairs({100, 200, 300, 500, 1000}) do
    n.request_to_generate_chunks({d, d}, 0)
    n.force_generate_chunk_requests()
    local ok = n.can_place_entity{name = "entity-ghost", inner_name = "iron-chest", position = {d + 0.5, d + 0.5},
      force = "player", build_check_type = BG}
    local okm = n.can_place_entity{name = "iron-chest", position = {d + 0.5, d + 0.5}, force = "player",
      build_check_type = defines.build_check_type.manual}
    lg.out(string.format("PDBG nauvis at %d,%d blueprint_ghost=%s manual=%s tile=%s", d, d, tostring(ok), tostring(okm),
      n.get_tile(d, d).name))
  end
  -- The same calls on nauvis, for contrast.
  for name, v in pairs(defines.build_check_type) do
    local ok2 = n.can_place_entity{name = "entity-ghost", inner_name = "iron-chest", position = {-40.5, -40.5},
      force = "player", build_check_type = v}
    lg.out(string.format("PDBG nauvis can_place check=%s ghost=%s", name, tostring(ok2)))
  end
end
hooks.P0 = function(inst) platform_answer(inst) end

function C.P()
  if not storage.platform_surface then return end
  local surface = game.surfaces[storage.platform_surface]
  lg.out("P charted_now platform_chunk_0_0=" .. tostring(charted(surface, 0, 0)))
  local tiles = surface.find_tiles_filtered{name = "space-platform-foundation"}
  local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
  for _, t in pairs(tiles) do
    x0, y0 = math.min(x0, t.position.x), math.min(y0, t.position.y)
    x1, y1 = math.max(x1, t.position.x), math.max(y1, t.position.y)
  end
  lg.out(string.format("P foundation tiles=%d bbox=%d,%d..%d,%d", #tiles, x0, y0, x1, y1))
  local mid = math.floor((y0 + y1) / 2) + 0.5
  local function stamp(case, design, pos, mode)
    return with_bp(design, function(s)
      return track.stamp(case, s, surface, pos, {verbose = true, tile_search = 3, build_mode = mode})
    end).id
  end
  storage.P1 = stamp("P1", bp.P, {x1 + 2.5, mid}, defines.build_mode.forced)
  storage.P2 = stamp("P2", bp.P, {x0 - 1.5, mid}, defines.build_mode.superforced)
  storage.P5 = stamp("P5", bp.P, {math.floor((x0 + x1) / 2) + 0.5, y1 + 2.5}, defines.build_mode.normal)
  storage.P3 = stamp("P3", bp.chest, {x1 + 0.5, y1 + 0.5}, defines.build_mode.forced)
  -- P7: the same chest stamp with skip_fog_of_war = true.
  storage.P7 = with_bp(bp.chest, function(s)
    return track.stamp("P7", s, surface, {x0 + 0.5, y1 + 0.5}, {verbose = true, skip_fog_of_war = true})
  end).id
  -- P6: a ghost made with create_entity (script check), tagged like a stamp.
  local g = surface.create_entity{name = "entity-ghost", inner_name = "iron-chest", position = {x1 + 0.5, y0 + 0.5},
    force = "player"}
  storage.P6 = track.adopt("P6", surface, {g}, {verbose = true}).id
end

function platform_answer(inst)
  lg.answer("Q11", inst.case .. "_entity_ghosts_created", inst.n_ghosts,
    string.format("tile_ghosts=%d platform_built=%d tagged=%d tiles_built=%d/%d tags=%s",
      inst.n_tiles, inst.paths.platform or 0, inst.built_tagged, inst.tiles_built, inst.n_tiles,
      lg.ser(inst.tags_seen)))
  if inst.n_ghosts > 0 then
    lg.verdict("Q11", inst.case .. "_platform_built_carries_tags",
      (inst.paths.platform or 0) == inst.n_ghosts and inst.built_tagged == inst.n_ghosts,
      string.format("platform_built=%d tagged=%d ghosts=%d", inst.paths.platform or 0, inst.built_tagged,
        inst.n_ghosts))
  end
  done(inst.case)
end

hooks.P1 = function(inst)
  platform_answer(inst)
  -- Two-phase: now that P1's foundation exists, stamp the chest onto it.
  local surface = game.surfaces[inst.surface_index]
  local cx = (inst.area[1][1] + inst.area[2][1]) / 2
  local cy = (inst.area[1][2] + inst.area[2][2]) / 2
  storage.P4 = with_bp(bp.chest, function(s)
    return track.stamp("P4", s, surface, {cx, cy}, {verbose = true})
  end).id
end
hooks.P2 = platform_answer
hooks.P6 = function(inst)
  platform_answer(inst)
  sched.at(game.tick + 30, "retire", inst.id)
end
hooks["P6:retired"] = function(inst)
  lg.verdict("Q11", "P6_platform_deconstructs_entity", inst.entities_gone == inst.retire_entities,
    string.format("entity_destroyed_events=%d/%d after_ticks=%d", inst.entities_gone, inst.retire_entities,
      game.tick - inst.retire_tick))
  done("P6r")
end
hooks.P7 = platform_answer
hooks.P3 = platform_answer
hooks.P4 = platform_answer
hooks.P5 = platform_answer

-- E2: the nauvis analogue: landfill tiles under a chest, stamped over water.
function C.L(surface)
  local water = {}
  for x = -42, -36 do
    for y = -2, 4 do water[#water + 1] = {name = "water", position = {x, y}} end
  end
  surface.set_tiles(water, false, true, true, false)
  local inst = with_bp(bp.L, function(s)
    return track.stamp("L", s, surface, {-39, 1}, {verbose = true})
  end)
  storage.L = inst.id
end

hooks.L = function(inst)
  lg.answer("E2", "landfill_under_entity_ghost_created", inst.n_ghosts == 1,
    string.format("entity_ghosts=%d tile_ghosts=%d built_tagged=%d tiles_built=%d", inst.n_ghosts,
      inst.n_tiles, inst.built_tagged, inst.tiles_built))
  done("L")
end

-- Driver ----------------------------------------------------------------------------

function C.stamp_all()
  local surface = game.surfaces.nauvis
  C.A(surface)
  C.S(surface)
  C.T(surface)
  C.M(surface)
  C.V(surface)
  C.R(surface)
  C.W(surface)
  C.C(surface)
  C.D(surface)
  C.L(surface)
  C.P_uncharted()
  if storage.platform_surface then
    -- P6 cannot finish headless (see FINDINGS), so it is reported but not awaited.
    storage.P_expect = {"P0", "P1", "P2", "P3", "P4", "P5", "P7"}
  end
  storage.expect = {"S", "T1", "T2", "M", "V", "R", "W", "C", "D", "A", "L", "M2"}
  for _, name in pairs(storage.P_expect or {}) do table.insert(storage.expect, name) end
  -- M2 runs once the network is idle; the chart probe last, since it researches everything.
  sched.at(1460, "M2")
  sched.at(3300, "chart_probe")
end

function C.status()
  local parts = {}
  for _, inst in pairs(storage.inst) do parts[#parts + 1] = inst.case .. "=" .. inst.state end
  lg.out("STATUS " .. table.concat(parts, " ") .. " stock=" .. lg.ser(rig.stock_counts()))
end

function C.check_all_done()
  if storage.all_done or not storage.expect then return end
  for _, name in pairs(storage.expect) do
    if not storage.done[name] then return end
  end
  storage.all_done = true
  lg.out("EVENT_COUNTS " .. lg.ser(storage.ev_count))
  lg.out("SCRIPT_RAISED_BUILT_BY_NAME " .. lg.ser(storage.raised_built))
  lg.out("UNTAGGED_BUILDS " .. lg.ser(storage.untagged))
  lg.out("ALL_DONE")
end

-- After everything else: does chart state gate blueprint placement?
sched.tasks.chart_probe = function()
  local force = game.forces.player
  local BG = defines.build_check_type.blueprint_ghost
  local function bg(surf, at)
    return surf.can_place_entity{name = "entity-ghost", inner_name = "iron-chest", position = at, force = force,
      build_check_type = BG}
  end
  local n, probe = game.surfaces.nauvis, game.surfaces["seb-probe"]
  if not probe then
    probe = game.create_surface("seb-probe")
    probe.request_to_generate_chunks({0, 0}, 1)
    probe.force_generate_chunk_requests()
  end
  if not storage.platform_surface then
    lg.out("BASEONLY new_surface blueprint_ghost=" .. tostring(bg(probe, {0.5, 0.5}))
      .. " script_ghost=" .. tostring(probe.can_place_entity{name = "entity-ghost", inner_name = "iron-chest",
        position = {0.5, 0.5}, force = force, build_check_type = defines.build_check_type.script_ghost}))
    return
  end
  local pf = game.surfaces[storage.platform_surface]
  lg.out(string.format("CHART before: nauvis=%s probe=%s platform=%s", tostring(bg(n, {-40.5, -40.5})),
    tostring(bg(probe, {0.5, 0.5})), tostring(bg(pf, {4.5, 4.5}))))
  local ok1, e1 = pcall(force.copy_chart, force, n, probe)
  local ok2, e2 = pcall(force.copy_chart, force, n, pf)
  lg.out(string.format("CHART after copy_chart(nauvis->probe ok=%s %s, nauvis->platform ok=%s %s): probe=%s platform=%s",
    tostring(ok1), tostring(e1 or ""), tostring(ok2), tostring(e2 or ""), tostring(bg(probe, {0.5, 0.5})),
    tostring(bg(pf, {4.5, 4.5}))))
  force.clear_chart(n)
  lg.out("CHART after clear_chart(nauvis): nauvis=" .. tostring(bg(n, {-40.5, -40.5})))
  lg.out(string.format("HIDDEN nauvis=%s probe=%s platform=%s", tostring(force.get_surface_hidden(n)),
    tostring(force.get_surface_hidden(probe)), tostring(force.get_surface_hidden(pf))))
  force.set_surface_hidden(probe, false)
  force.set_surface_hidden(pf, false)
  lg.out(string.format("HIDDEN after set_surface_hidden(false): probe=%s platform=%s",
    tostring(bg(probe, {0.5, 0.5})), tostring(bg(pf, {4.5, 4.5}))))
  local planet = game.planets["vulcanus"]
  local ok_a, err_a = pcall(planet.associate_surface, probe)
  lg.out(string.format("PLANET associate probe->vulcanus ok=%s %s vulcanus_unlocked=%s probe=%s",
    tostring(ok_a), tostring(err_a or ""), tostring(force.is_space_location_unlocked("vulcanus")),
    tostring(bg(probe, {0.5, 0.5}))))
  force.unlock_space_location("vulcanus")
  lg.out(string.format("PLANET after unlock vulcanus: probe=%s", tostring(bg(probe, {0.5, 0.5}))))
  force.research_all_technologies()
  lg.out(string.format("RESEARCH after research_all: platform=%s platforms_unlocked=%s",
    tostring(bg(pf, {4.5, 4.5})), tostring(force.is_space_platforms_unlocked())))
end

return C
