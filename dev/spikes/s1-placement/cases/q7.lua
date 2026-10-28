-- Q7 calibration surface: same offsets as nauvis? events? anything left behind?
local fmt = require("lib.fmt")
local G = require("lib.geom")
local B = require("lib.bp")
local D = require("lib.designs")
local Rng = require("lib.rng")
local events = require("lib.events")
local Q = {id = "Q7"}

local DIRS = {0, 4, 8, 12}
local MARKER = "seb-spike-marker"
local NAME = "seb-spike-calibration"
local ORIGIN = {x = 0, y = 0}

local function surface()
  local s = game.get_surface(NAME)
  if s then return s end
  s = game.create_surface(NAME)
  s.generate_with_lab_tiles = true
  s.request_to_generate_chunks(ORIGIN, 2)
  s.force_generate_chunk_requests()
  return s
end

local function designs()
  local list = {}
  for _, id in ipairs({"a", "a_shift", "b", "c", "c2", "g1", "g2", "g3", "g4", "q4", "e", "e2"}) do
    list[#list + 1] = B.new(D[id])
  end
  for _, id in ipairs({"d1", "d2", "d3", "d4", "d5"}) do
    if storage.exports[id] then list[#list + 1] = B.from_export(id, storage.exports[id]) end
  end
  return list
end

local function count_events(w)
  local parts = {}
  for k, v in pairs(w) do parts[#parts + 1] = k .. "=" .. v end
  table.sort(parts)
  return #parts == 0 and "none" or table.concat(parts, ",")
end

local function calibrate_all(s, raise_built, force)
  local list = designs()
  local equal, total, diffs = 0, 0, {}
  for _, bp in ipairs(list) do
    for _, d in ipairs(DIRS) do
      local rec = B.stamp(bp, s, ORIGIN, d, {raise_built = raise_built, radius = 64, force = force})
      total = total + 1
      local want = storage.sig[bp.id .. "/" .. d]
      if want and B.sig(rec) == want then
        equal = equal + 1
      else
        diffs[#diffs + 1] = bp.id .. "/" .. d .. ":" .. B.sig(rec) .. " vs " .. tostring(want)
      end
    end
    bp.inv.destroy()
  end
  return equal, total, diffs
end

function Q.run()
  local before = #game.surfaces
  local s = surface()
  local gen = 0
  for _ in s.get_chunks() do gen = gen + 1 end
  fmt.out("Q7.surface", s.name, "index=" .. s.index, "surfaces " .. before .. "->" .. #game.surfaces,
    "generated_chunks=" .. gen, "entities=" .. s.count_entities_filtered({}),
    "tile(0,0)=" .. s.get_tile(0, 0).name, "tile(60,-60)=" .. s.get_tile(60, -60).name)
  events.start()
  local equal, total, diffs = calibrate_all(s, false)
  local w = events.stop()
  fmt.verdict("Q7.offsets raise_built=false", equal == total, "equal_to_nauvis=" .. equal .. "/" .. total,
    "events_during=" .. count_events(w), table.concat(diffs, " | "))
  fmt.verdict("Q7.leftovers", s.count_entities_filtered({}) == 0, "entities_after_destroy=" .. s.count_entities_filtered({}),
    "ghosts=" .. s.count_entities_filtered({type = {"entity-ghost", "tile-ghost"}}))
  local eq2, tot2, diffs2 = calibrate_all(s, false, "seb-other")
  fmt.verdict("Q7.offsets force=seb-other", eq2 == tot2, "equal_to_nauvis_player=" .. eq2 .. "/" .. tot2,
    table.concat(diffs2, " | "))
  -- positive control: the same stamp with raise_built = true must raise script_raised_built
  local bp = B.new(D.g2)
  events.start()
  local rec = B.stamp(bp, s, ORIGIN, 0, {raise_built = true, radius = 64})
  local w2 = events.stop()
  fmt.out("Q7.control raise_built=true g2 (1 entity + 4 tiles) n_ret=" .. rec.n_ret, "events=" .. count_events(w2))
  bp.inv.destroy()
  -- ungenerated chunk on the calibration surface
  local far = {x = 1000, y = 1000}
  local gen_before = s.is_chunk_generated({x = 31, y = 31})
  local bpa = B.new(D.a)
  local ok, recf = pcall(B.stamp, bpa, s, far, 0, {raise_built = false, radius = 16})
  fmt.out("Q7.ungenerated chunk_generated_before=" .. tostring(gen_before), "call_ok=" .. tostring(ok),
    "n_ret=" .. tostring(ok and recf.n_ret or recf), "chunk_generated_after=" .. tostring(s.is_chunk_generated({x = 31, y = 31})))
  bpa.inv.destroy()
  Q.place()
end

-- End to end, the way the mod will place a child: calibrate the entry marker's
-- offset per direction on the hidden surface, then stamp on nauvis at
-- P = W - off_d and check the entry ghost lands on W facing (D + d) % 16.
local function entry_offsets(bp, marker_i)
  local offs = {}
  for _, d in ipairs(DIRS) do
    local rec = B.stamp(bp, surface(), ORIGIN, d, {raise_built = false, radius = 64})
    for _, g in pairs(rec.ghosts) do
      if g.kind == "e" and g.i == marker_i then offs[d] = {off = g.pos, dir = g.dir} end
    end
  end
  return offs
end

local function place_item(bp, marker_i, rng, st)
  local offs = entry_offsets(bp, marker_i)
  for _ = 1, 5 do
    local W = {x = rng:int(-90, 90) + 0.5, y = rng:int(-90, 90) + 0.5}
    for _, d in ipairs(DIRS) do
      local P = G.sub(W, offs[d].off)
      local rec = B.stamp(bp, game.surfaces.nauvis, P, d, {radius = 64})
      local hit = false
      for _, g in pairs(rec.ghosts) do
        if g.kind == "e" and g.i == marker_i and G.same(g.pos, W) and g.dir == offs[d].dir then hit = true end
      end
      local odd = (P.x % 2 ~= 0) or (P.y % 2 ~= 0)
      local key = odd and "odd" or "even"
      st[key .. "_n"] = st[key .. "_n"] + 1
      if hit then st[key .. "_hit"] = st[key .. "_hit"] + 1 end
      if P.x ~= math.floor(P.x) or P.y ~= math.floor(P.y) then st.nonint = st.nonint + 1 end
    end
  end
end

local function new_place_stats() return {even_n = 0, even_hit = 0, odd_n = 0, odd_hit = 0, nonint = 0} end

function Q.place()
  local rng = Rng.new(31337)
  local st1 = new_place_stats()
  local n1 = 0
  for _, spec in ipairs(D.random(555, 40)) do
    if #spec.entities > 0 then
      local c = D.copy_spec(spec, spec.id .. "+entry")
      local tb = G.bounds(c.entities, c.tiles, "tile")
      local x, y = rng:int(tb.l - 1, tb.r), rng:int(tb.t - 1, tb.b)
      c.entities[#c.entities + 1] = D.ent(MARKER, x + 0.5, y + 0.5, rng:pick(DIRS))
      local bp = B.new(c)
      place_item(bp, #c.entities, rng, st1)
      bp.inv.destroy()
      n1 = n1 + 1
    end
  end
  local hits1, total1 = st1.even_hit + st1.odd_hit, st1.even_n + st1.odd_n
  fmt.verdict("Q7.place grid-1 designs", hits1 == total1, "designs=" .. n1, "stamps=" .. total1,
    "entry_on_target=" .. hits1, "non_integer_P=" .. st1.nonint)
  -- rail designs (2-tile grid) with an entry marker
  local st2 = new_place_stats()
  for _, id in ipairs({"d3", "d5"}) do
    local bp = B.from_export(id .. "+entry", storage.exports[id])
    local ents = bp.stack.get_blueprint_entities()
    local tb = G.bounds(ents, nil, "tile")
    ents[#ents + 1] = {entity_number = #ents + 1, name = MARKER, position = {x = tb.l + 0.5, y = tb.t + 0.5},
      direction = 4, tags = {i = #ents + 1}}
    bp.stack.set_blueprint_entities(ents)
    B.read(bp)
    for _ = 1, 4 do place_item(bp, #ents, rng, st2) end
    bp.inv.destroy()
  end
  fmt.verdict("Q7.place rail designs", st2.even_hit == st2.even_n and st2.odd_hit == 0,
    "P_even: entry_on_target=" .. st2.even_hit .. "/" .. st2.even_n,
    "P_odd: entry_on_target=" .. st2.odd_hit .. "/" .. st2.odd_n)
end

-- Tick 5: calibrate with raise_built = false while watching, and register one
-- ghost for on_object_destroyed as a positive control.
function Q.tick_start()
  local s = surface()
  events.start()
  local equal, total = calibrate_all(s, false)
  local bp = B.new(D.a)
  local ret = bp.stack.build_blueprint({surface = s, force = "player", position = {x = 10, y = 10}, direction = 0,
    build_mode = defines.build_mode.forced, raise_built = false})
  local reg = script.register_on_object_destroyed(ret[1])
  for _, g in pairs(ret) do g.destroy() end
  bp.inv.destroy()
  storage.q7 = {equal = equal, total = total, reg = reg, tick = game.tick}
end

-- Positive control in a running game: raise_built = true must raise
-- script_raised_built (for entity ghosts and, possibly, tile ghosts).
function Q.tick_control()
  local s = surface()
  for _, id in ipairs({"g2", "a"}) do
    local bp = B.new(D[id])
    events.start()
    local rec = B.stamp(bp, s, ORIGIN, 0, {raise_built = true, radius = 64})
    local w = events.stop()
    events.start()
    local rec2 = B.stamp(bp, s, ORIGIN, 0, {raise_built = false, radius = 64})
    local w2 = events.stop()
    fmt.verdict("Q7.control tick=" .. game.tick .. " " .. id, (w.script_raised_built or 0) == rec.n_ret
      and (w2.script_raised_built or 0) == 0,
      "raise_built=true n_ret=" .. rec.n_ret .. "(e" .. rec.ret_e .. "+t" .. rec.ret_t .. ") events=" .. count_events(w),
      "| raise_built=false n_ret=" .. rec2.n_ret .. " events=" .. count_events(w2))
    bp.inv.destroy()
  end
end

function Q.tick_report()
  local w = events.stop()
  local st = storage.q7 or {}
  fmt.verdict("Q7.tick calibration in a running game", st.equal == st.total and (w.script_raised_built or 0) == 0
    and (w.on_built_entity or 0) == 0, "equal_to_nauvis=" .. tostring(st.equal) .. "/" .. tostring(st.total),
    "events_ticks_" .. tostring(st.tick) .. "_to_" .. game.tick .. "=" .. count_events(w),
    "(1 ghost was registered for on_object_destroyed as a positive control)",
    "entities_left=" .. surface().count_entities_filtered({}))
end

return Q
