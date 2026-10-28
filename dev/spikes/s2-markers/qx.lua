-- QX Extras: prototype facts for the marker candidates, and wires. Can a wire attach to the combinator
-- marker, do its signals leak into a connected network, does enabled = false silence it, and does
-- circuit_wire_max_distance = 0 keep wires off? Band y=130; the network is read on later ticks.
local lib = require("lib")
local q = {id = "QX"}

local Y = 130.5
local RED = defines.wire_connector_id.circuit_red

local function proto_facts()
  for _, name in ipairs({lib.SOCKET, lib.NOWIRE, lib.NOFRG, lib.TAG, "constant-combinator"}) do
    local p = prototypes.entity[name]
    lib.log("QX proto name=" .. name, "type=" .. p.type, "collision_mask=" .. lib.ser(p.collision_mask.layers),
      "fast_replaceable_group=" .. tostring(p.fast_replaceable_group), "supports_direction=" .. tostring(p.supports_direction),
      "max_circuit_wire_distance=" .. p.get_max_circuit_wire_distance(), "flags=" .. lib.ser(p.flags),
      "items_to_place_this=" .. lib.ser(p.items_to_place_this))
  end
  local item = prototypes.item[lib.SOCKET]
  lib.log("QX item name=" .. lib.SOCKET, "flags=" .. lib.ser(item.flags), "hidden=" .. tostring(item.hidden))
end

local function wire(s, name, x, reach_check)
  local m = s.create_entity{name = name, position = {x + 0.5, Y}, direction = lib.E, force = "player"}
  lib.configure(m, "wired", {{name = lib.SIGNAL, count = 42}})
  local pole = s.create_entity{name = "medium-electric-pole", position = {x + 3.5, Y}, force = "player"}
  local mc = m.get_wire_connector(RED, true)
  local pc = pole.get_wire_connector(RED, true)
  local ok, res = lib.try(function() return mc.connect_to(pc, reach_check) end)
  local _, reach = lib.try(function() return mc.can_wire_reach(pc) end)
  lib.log("QX wire marker=" .. name, "reach_check=" .. tostring(reach_check), "connect ok=" .. tostring(ok),
    "result=" .. tostring(res), "can_wire_reach=" .. tostring(reach), "connections=" .. mc.connection_count)
  return {marker = m, pole = pole, name = name, reach_check = reach_check}
end

-- A disabled marker (is_on = false): is the flag captured and stamped, and are the signals still readable?
local function disabled_marker(s)
  local m = s.create_entity{name = lib.SOCKET, position = {40.5, Y}, direction = lib.E, force = "player"}
  lib.configure(m, "disabled", {{name = lib.SIGNAL, count = 42}})
  m.get_control_behavior().enabled = false
  local inv, bp = lib.new_bp()
  bp.create_blueprint{surface = s, force = "player", area = lib.tile_area({x = 40.5, y = Y})}
  local be = lib.find_be(bp.get_blueprint_entities(), lib.SOCKET)
  local ghost
  for _, g in ipairs(bp.build_blueprint{surface = s, force = "player", position = {40.5, Y + 4}}) do
    if g.valid and g.ghost_name == lib.SOCKET then ghost = g end
  end
  local r = ghost and lib.read_cc(ghost)
  local n, c = lib.live_first_filter(r)
  local is_on = be and be.control_behavior and be.control_behavior.is_on
  lib.log("QX disabled captured_is_on=" .. tostring(is_on), "ghost=" .. lib.ser(r))
  lib.verdict("QX disabled_roundtrip", is_on == false and type(r) == "table" and type(r.cb) == "table" and r.cb.enabled == false
    and n == lib.SIGNAL and c == 42, "is_on=false is captured and stamped; signals stay readable")
  inv.destroy()
end

-- Copy settings (what shift-right-click / shift-left-click does) between markers and real combinators.
local function copy_settings(s)
  local y = Y + 8
  local function marker(name, x, desc, sig, count)
    local e = s.create_entity{name = name, position = {x, y}, direction = lib.E, force = "player"}
    if desc then lib.configure(e, desc, {{name = sig, count = count}}) end
    return e
  end
  local src = marker(lib.SOCKET, 0.5, "source", lib.SIGNAL, 11)
  local cc_src = marker("constant-combinator", 2.5, "real cc", "signal-A", 3)
  local pairs_to_try = {
    {id = "socket<-socket", dst = marker(lib.SOCKET, 4.5), src = src},
    {id = "nofrg<-socket", dst = marker(lib.NOFRG, 6.5), src = src},
    {id = "cc<-socket", dst = marker("constant-combinator", 8.5), src = src},
    {id = "socket<-cc", dst = marker(lib.SOCKET, 10.5), src = cc_src},
    {id = "tag<-socket", dst = marker(lib.TAG, 12.5), src = src},
  }
  for _, p in ipairs(pairs_to_try) do
    local ok, res = lib.try(function() return p.dst.copy_settings(p.src) end)
    local read = p.dst.type == "constant-combinator" and lib.ser(lib.read_cc(p.dst)) or "n/a"
    lib.log("QX copy_settings " .. p.id, "ok=" .. tostring(ok), ok and ("removed=" .. lib.ser(res)) or ("err=" .. res), "dst=" .. read)
  end
end

-- Fast replace between a marker and a real constant combinator, both ways.
local function fast_replace(s)
  local y = Y + 12
  local function place(name, x)
    return s.create_entity{name = name, position = {x, y}, direction = lib.E, force = "player"}
  end
  local cases = {
    {id = "cc_over_socket", base = lib.SOCKET, new = "constant-combinator", x = 0.5},
    {id = "socket_over_cc", base = "constant-combinator", new = lib.SOCKET, x = 4.5},
    {id = "cc_over_nofrg", base = lib.NOFRG, new = "constant-combinator", x = 8.5},
    {id = "nofrg_over_cc", base = "constant-combinator", new = lib.NOFRG, x = 12.5},
  }
  for _, c in ipairs(cases) do
    local base = place(c.base, c.x)
    local can = s.can_fast_replace{name = c.new, position = {c.x, y}, direction = lib.E, force = "player"}
    local ok, e = lib.try(function()
      return s.create_entity{name = c.new, position = {c.x, y}, direction = lib.E, force = "player", fast_replace = true, spill = false}
    end)
    local left = {}
    for _, f in ipairs(s.find_entities_filtered{area = lib.tile_area({x = c.x, y = y})}) do left[#left + 1] = f.name end
    lib.log("QX fast_replace " .. c.id, "can_fast_replace=" .. tostring(can), "create ok=" .. tostring(ok),
      "base_still_valid=" .. tostring(base.valid), "on_tile=" .. table.concat(left, ","))
  end
end

-- Logistic groups: a marker section in a named group shares content force-wide. What does the blueprint
-- store, and what does a stamped ghost read once the group's content has changed?
local function logistic_group(s)
  local y = Y + 16
  local a = s.create_entity{name = lib.SOCKET, position = {0.5, y}, direction = lib.E, force = "player"}
  local sec = a.get_or_create_control_behavior().get_section(1)
  local okg, gerr = lib.try(function() sec.group = "seb-spike-group" end)
  sec.set_slot(1, lib.slot(lib.SIGNAL, 42))
  local b = s.create_entity{name = lib.SOCKET, position = {4.5, y}, direction = lib.E, force = "player"}
  local bsec = b.get_or_create_control_behavior().get_section(1)
  bsec.group = "seb-spike-group"
  local b_sees = lib.ser(bsec.filters)
  local inv, bp = lib.new_bp()
  bp.create_blueprint{surface = s, force = "player", area = lib.tile_area({x = 0.5, y = y})}
  local be = lib.find_be(bp.get_blueprint_entities(), lib.SOCKET)
  bsec.set_slot(1, lib.slot(lib.SIGNAL, 99))
  local a_after = lib.ser(sec.filters)
  local ghost
  for _, g in ipairs(bp.build_blueprint{surface = s, force = "player", position = {8.5, y}}) do
    if g.valid and g.ghost_name == lib.SOCKET then ghost = g end
  end
  local ghost_sees = ghost and lib.ser(ghost.get_control_behavior().get_section(1).filters) or "no ghost"
  local ghost_group = ghost and ghost.get_control_behavior().get_section(1).group or "-"
  lib.log("QX group set ok=" .. tostring(okg) .. (okg and "" or (" err=" .. gerr)), "b_joins_group_sees=" .. b_sees)
  lib.log("QX group blueprint_section=" .. lib.ser(be and be.control_behavior), "a_after_b_edit=" .. a_after)
  lib.log("QX group ghost_group=" .. ghost_group, "ghost_sees=" .. ghost_sees)
  inv.destroy()
end

function q.run(ctx)
  local s = ctx.surface
  lib.case("QX proto", proto_facts)
  lib.case("QX group", function() logistic_group(s) end)
  lib.case("QX disabled", function() disabled_marker(s) end)
  lib.case("QX copy_settings", function() copy_settings(s) end)
  lib.case("QX fast_replace", function() fast_replace(s) end)
  storage.qx = {
    wire(s, lib.SOCKET, 0, false),
    wire(s, lib.SOCKET, 8, true),
    wire(s, lib.NOWIRE, 16, false),
    wire(s, lib.NOWIRE, 24, true),
  }
end

local function network_signals(pole)
  local net = pole.get_circuit_network(RED)
  if not net then return "no_network" end
  return lib.ser(net.signals or {})
end

function q.on_tick(e)
  if not storage.qx then return end
  if e.tick == 120 or e.tick == 240 then
    for _, w in ipairs(storage.qx) do
      lib.log("QX signals tick=" .. e.tick, "marker=" .. w.name, "reach_check=" .. tostring(w.reach_check),
        "enabled=" .. tostring(w.marker.get_control_behavior().enabled), "network=" .. network_signals(w.pole))
    end
  end
  if e.tick == 180 then
    for _, w in ipairs(storage.qx) do w.marker.get_control_behavior().enabled = false end
    lib.log("QX disabled all wired markers at tick 180")
  end
end

return q
