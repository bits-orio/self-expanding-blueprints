-- Spike: LuaEntity.get_signals_changed (Factorio 2.1.21 and newer). See
-- FINDINGS.md. Runs in the game's test mode from scenarios/probe; every
-- result is a log line starting "SC ". The steps are scheduled by tick:
--
--   2          build: constant combinator -> lamp and arithmetic combinator
--              (red), combinator output -> lamp3, chest -> pole, and things
--              that are never wired (lamp2, furnace, belt)
--   3..10      wire it all; what the call says right after wiring
--   19..24     a value change at tick 20
--   39..44     a signal type change at tick 40
--   49..54     a chest insert at tick 50
--   60..120    changes at 70 and 75, then the tick argument at 120
--   139..153   a wire removed at 140 and put back at 150
--   158, 160   connectors that do not exist, odd tick arguments
--   170..177   cost on a 300-signal network
--   180        the control behavior fields added with 2.1.25
--   185        done
local W = defines.wire_connector_id
local RED, GREEN = W.circuit_red, W.circuit_green
local ents = {}

local function say(s) log("SC " .. s) end

-- tostring of a call's result, or "ERR <message>" when it throws.
local function guarded(f)
  local ok, r = pcall(f)
  return ok and tostring(r) or ("ERR " .. tostring(r):sub(1, 120))
end

local function lamp_changed(id) return guarded(function() return ents.lamp.get_signals_changed(id) end) end

local function set_combinator(entity, name, count)
  local behavior = entity.get_control_behavior()
  local section = behavior.get_section(1) or behavior.add_section()
  section.filters = { { value = { type = "item", name = name, quality = "normal", comparator = "=" }, min = count } }
end

local function connector(entity, id) return entity.get_wire_connector(id, true) end

local function wire(a, id_a, b, id_b)
  assert(connector(a, id_a).connect_to(connector(b, id_b), false, defines.wire_origin.player))
end

local function build()
  local surface = game.surfaces.nauvis
  surface.request_to_generate_chunks({ 0, 0 }, 2)
  surface.force_generate_chunk_requests()
  local function make(name, x, y, extra)
    extra = extra or {}
    extra.name, extra.position, extra.force = name, { x, y }, "player"
    return assert(surface.create_entity(extra), name)
  end
  ents.cc = make("constant-combinator", 0, 0)
  ents.lamp = make("small-lamp", 2, 0)
  ents.arith = make("arithmetic-combinator", 5, 0, { direction = defines.direction.east })
  ents.lamp3 = make("small-lamp", 8, 3)
  ents.lamp2 = make("small-lamp", 8, 0) -- never wired
  ents.chest = make("wooden-chest", -4, 0)
  ents.pole = make("small-electric-pole", -4, 3)
  ents.furnace = make("stone-furnace", 12, 0)
  ents.belt = make("transport-belt", 14, 0)
  -- Power for the arithmetic combinator: without it its output never changes.
  make("small-electric-pole", 5, 2)
  local power = make("electric-energy-interface", 5, 4)
  power.power_production, power.electric_buffer_size, power.energy = 1e6, 1e6, 1e6
end

local function wire_up()
  wire(ents.cc, RED, ents.lamp, RED)
  wire(ents.cc, RED, ents.arith, W.combinator_input_red)
  wire(ents.chest, RED, ents.pole, RED)
  wire(ents.arith, W.combinator_output_red, ents.lamp3, RED)
  ents.arith.get_control_behavior().parameters = {
    first_signal = { type = "item", name = "iron-plate" }, second_constant = 2, operation = "*",
    output_signal = { type = "item", name = "iron-plate" },
  }
  set_combinator(ents.cc, "iron-plate", 3)
  say("T3 wired; cc=iron-plate 3 (set same tick as wiring)")
end

-- One line with get_signals_changed (no tick argument) on every connector.
local function query(tag)
  say(("%s tick=%d lamp_red=%s lamp_green=%s | cc_red=%s | arith_in_red=%s arith_in_green=%s arith_out_red=%s lamp3_red(on arith out)=%s | chest_red=%s pole_red=%s | lamp2_red(unwired)=%s | furn_red=%s belt_red=%s lamp_combinator_in(bad id)=%s")
    :format(tag, game.tick, lamp_changed(RED), lamp_changed(GREEN), tostring(ents.cc.get_signals_changed(RED)),
      tostring(ents.arith.get_signals_changed(W.combinator_input_red)),
      tostring(ents.arith.get_signals_changed(W.combinator_input_green)),
      tostring(ents.arith.get_signals_changed(W.combinator_output_red)),
      tostring(ents.lamp3.get_signals_changed(RED)),
      tostring(ents.chest.get_signals_changed(RED)), tostring(ents.pole.get_signals_changed(RED)),
      tostring(ents.lamp2.get_signals_changed(RED)),
      guarded(function() return ents.furnace.get_signals_changed(RED) end),
      guarded(function() return ents.belt.get_signals_changed(RED) end),
      guarded(function() return ents.lamp.get_signals_changed(W.combinator_input_red) end)))
end

-- Steps by tick; several steps on one tick run in the order they were added.
local schedule = {}
local function at(tick, step)
  local earlier = schedule[tick]
  schedule[tick] = earlier and function() earlier() step() end or step
end

at(3, wire_up)
for t = 3, 10 do at(t, function() query("quiet") end) end

for t = 19, 24 do
  at(t, function()
    if t == 20 then
      set_combinator(ents.cc, "iron-plate", 9)
      say("T20 changed value 3->9 BEFORE query")
    end
    query("val")
  end)
end
at(20, function()
  say("T20 twice-same-tick: " .. lamp_changed(RED) .. " " .. lamp_changed(RED)
    .. " then with tick arg 19: " .. tostring(ents.lamp.get_signals_changed(RED, 19))
    .. " arg 20: " .. tostring(ents.lamp.get_signals_changed(RED, 20)))
end)

for t = 39, 44 do
  at(t, function()
    if t == 40 then
      set_combinator(ents.cc, "copper-plate", 9)
      say("T40 changed type iron->copper same count")
    end
    query("type")
  end)
end

for t = 49, 54 do
  at(t, function()
    if t == 50 then
      ents.chest.insert { name = "coal", count = 10 }
      say("T50 chest insert coal 10")
    end
    query("chest")
  end)
end

-- A poll every 60 ticks: the value changes at 70 and is back at 75.
at(60, function()
  set_combinator(ents.cc, "copper-plate", 9)
  say("T60 baseline poll no-arg=" .. lamp_changed(RED))
  query("base60")
end)
at(70, function() set_combinator(ents.cc, "copper-plate", 77) say("T70 value 9->77") end)
at(75, function() set_combinator(ents.cc, "copper-plate", 9) say("T75 value back to 9") end)
at(120, function()
  local function since(tick) return tostring(ents.lamp.get_signals_changed(RED, tick)) end
  say("T120 poll (no arg)=" .. lamp_changed(RED) .. "  poll(arg=60)=" .. since(60) .. "  poll(arg=76)=" .. since(76)
    .. "  poll(arg=70)=" .. since(70) .. " poll(arg=75)=" .. since(75) .. " poll(arg=74)=" .. since(74))
  say("T120 value now=" .. serpent.line(ents.lamp.get_signals(RED)))
end)

at(140, function()
  connector(ents.cc, RED).disconnect_from(connector(ents.lamp, RED), defines.wire_origin.player)
  say("T140 disconnected cc-lamp")
end)
for t = 139, 143 do at(t, function() query("unwire") end) end
at(150, function() wire(ents.cc, RED, ents.lamp, RED) say("T150 reconnected") end)
for t = 149, 153 do at(t, function() query("rewire") end) end

at(24, function()
  say("T24 lamp3 signals=" .. serpent.line(ents.lamp3.get_signals(RED)) .. " arith cb params="
    .. serpent.line(ents.arith.get_control_behavior().parameters))
end)

at(158, function()
  say("T158 lamp2 (never wired) before create connector: " .. tostring(ents.lamp2.get_signals_changed(RED)))
  connector(ents.lamp2, RED)
  say("T158 lamp2 after get_wire_connector(create=true): " .. tostring(ents.lamp2.get_signals_changed(RED)))
  say("T158 id values: circuit_red=" .. RED .. " circuit_green=" .. GREEN .. " comb_in_red=" .. W.combinator_input_red
    .. " comb_out_red=" .. W.combinator_output_red .. " pole_copper=" .. W.pole_copper)
  say("T158 pole.get_signals_changed(pole_copper)=" .. tostring(ents.pole.get_signals_changed(W.pole_copper))
    .. " lamp.get_signals_changed(pole_copper)=" .. tostring(ents.lamp.get_signals_changed(W.pole_copper)))
end)
at(160, function()
  say("T160 arg=-5 -> " .. guarded(function() return ents.lamp.get_signals_changed(RED, -5) end))
  say("T160 arg=99999 (future) -> " .. tostring(ents.lamp.get_signals_changed(RED, 99999)))
  say("T160 arg=0 -> " .. tostring(ents.lamp.get_signals_changed(RED, 0)))
end)

-- Cost: a constant combinator with up to 300 item signals on a lamp.
at(170, function()
  local items = {}
  for name in pairs(prototypes.item) do items[#items + 1] = name end
  table.sort(items)
  local surface = game.surfaces.nauvis
  local big = surface.create_entity { name = "constant-combinator", position = { 0, 10 }, force = "player" }
  local behavior = big.get_control_behavior()
  local section = behavior.get_section(1) or behavior.add_section()
  local filters = {}
  for i = 1, math.min(#items, 300) do
    filters[i] = { value = { type = "item", name = items[i], quality = "normal", comparator = "=" }, min = i }
  end
  section.filters = filters
  local lamp = surface.create_entity { name = "small-lamp", position = { 2, 10 }, force = "player" }
  connector(big, RED).connect_to(connector(lamp, RED), false, defines.wire_origin.player)
  ents.big, ents.biglamp = big, lamp
  say("T170 big network: items=" .. #items .. " signals=" .. #(lamp.get_signals(RED) or {}))
end)
at(172, function()
  local lamp, N = ents.biglamp, 2000
  local p1, p2, p3, p4 = helpers.create_profiler(), helpers.create_profiler(), helpers.create_profiler(), helpers.create_profiler()
  p1.reset() for _ = 1, N do local _ = lamp.get_signals(RED) end p1.stop()
  p2.reset() for _ = 1, N do local _ = lamp.get_signals_changed(RED) end p2.stop()
  p3.reset() for _ = 1, N do local _ = lamp.get_signals_changed(RED, 100) end p3.stop()
  p4.reset() for _ = 1, N do local _ = lamp.get_signal({ type = "item", name = "iron-plate" }, RED) end p4.stop()
  say("T172 signals on the big network=" .. #(lamp.get_signals(RED) or {}))
  log({ "", "SC T172 COST x" .. N .. " get_signals: ", p1 })
  log({ "", "SC COST x" .. N .. " get_signals_changed(no arg): ", p2 })
  log({ "", "SC COST x" .. N .. " get_signals_changed(arg): ", p3 })
  log({ "", "SC COST x" .. N .. " get_signal(single): ", p4 })
end)
at(175, function()
  local section = ents.big.get_control_behavior().get_section(1)
  local filters = section.filters
  filters[1].min = 999
  section.filters = filters
  say("T175 big net changed; changed=" .. tostring(ents.biglamp.get_signals_changed(RED)))
end)
at(176, function() say("T176 big changed=" .. tostring(ents.biglamp.get_signals_changed(RED))) end)
at(177, function() say("T177 big changed=" .. tostring(ents.biglamp.get_signals_changed(RED))) end)

-- Control behavior fields that came with 2.1.25: present and writable?
at(180, function()
  local surface = game.surfaces.nauvis
  local chest = ents.chest.get_or_create_control_behavior()
  say("T180 chest cb type=" .. tostring(chest.type) .. " read_empty_slots=" .. tostring(chest.read_empty_slots)
    .. " empty_slots_signal=" .. serpent.line(chest.empty_slots_signal))
  chest.read_empty_slots = true
  say("  chest set read_empty_slots=true -> " .. tostring(chest.read_empty_slots) .. " signals=" .. serpent.line(ents.pole.get_signals(RED)))
  local silo = surface.create_entity { name = "rocket-silo", position = { 30, 30 }, force = "player" }
  local silo_cb = silo.get_or_create_control_behavior()
  say("  silo cb type=" .. tostring(silo_cb.type) .. " read_launched=" .. tostring(silo_cb.read_launched)
    .. " launched_signal=" .. serpent.line(silo_cb.launched_signal))
  local selector = surface.create_entity { name = "selector-combinator", position = { 20, 0 }, force = "player",
    direction = defines.direction.east }
  local selector_cb = selector.get_or_create_control_behavior()
  say("  selector cb type=" .. tostring(selector_cb.type) .. " params=" .. serpent.line(selector_cb.parameters))
  selector_cb.parameters = { operation = "select", index_comparator = ">", index_constant = 2, select_max = true }
  say("  selector after set=" .. serpent.line(selector_cb.parameters))
end)

at(185, function()
  say("SC_DONE")
  script.finish_test(true)
end)

script.on_event(defines.events.on_tick, function(e)
  if e.tick == 2 then build() end
  local step = schedule[e.tick]
  if step then step() end
end)
