-- Q2 Capture of settings: does create_blueprint capture a marker's direction, description and signals,
-- for a real marker and for a ghost marker? Can a ghost's settings be written through the API?
-- Band y=60. Leaves ctx.bp_real (a captured blueprint) for Q3 and Q4.
local lib = require("lib")
local q = {id = "Q2"}

local Y = 60.5

local function check_be(id, be, want_desc, want_count)
  if not be then
    lib.verdict(id, false, "marker missing from blueprint")
    return
  end
  local name, count = lib.bp_first_filter(be)
  lib.log(id, "entity=" .. lib.ser(be))
  lib.verdict(id, be.direction == lib.E and be.player_description == want_desc and name == lib.SIGNAL and count == want_count,
    string.format("direction=%s player_description=%s filter=%s/%s", tostring(be.direction), tostring(be.player_description),
      tostring(name), tostring(count)))
end

local function capture(surface, area)
  local inv, bp = lib.new_bp()
  local ok, mapping = lib.try(function()
    return bp.create_blueprint{surface = surface, force = "player", area = area}
  end)
  if not ok then lib.log("Q2 create_blueprint ERR " .. mapping) end
  return inv, bp, bp.get_blueprint_entities() or {}
end

local function real_marker(ctx)
  local s = ctx.surface
  local m = s.create_entity{name = lib.SOCKET, position = {0.5, Y}, direction = lib.E, force = "player"}
  local steps = lib.configure(m, "Solar block", {{name = lib.SIGNAL, count = 42}})
  lib.log("Q2 real configure " .. lib.ser(steps))
  lib.log("Q2 real readback " .. lib.ser(lib.read_cc(m)))
  s.create_entity{name = "wooden-chest", position = {2.5, Y}, force = "player"}
  local inv, bp, ents = capture(s, {{-0.5, Y - 1}, {3.5, Y + 1}})
  lib.log("Q2 real captured count=" .. #ents)
  check_be("Q2 capture_real", lib.find_be(ents, lib.SOCKET), "Solar block", 42)
  ctx.bp_real = inv
end

local function real_marker_by_params(ctx)
  local s = ctx.surface
  local ok, m = lib.try(function()
    return s.create_entity{name = lib.SOCKET, position = {8.5, Y}, direction = lib.E, force = "player",
      player_description = "Param block", control_behavior = lib.bp_cb({{name = lib.SIGNAL, count = 45}})}
  end)
  if not ok then
    lib.log("Q2 real_params create ERR " .. m)
    return
  end
  local r = lib.read_cc(m)
  local name, count = lib.live_first_filter(r)
  lib.log("Q2 real_params readback " .. lib.ser(r))
  lib.verdict("Q2 real_params", r.desc == "Param block" and name == lib.SIGNAL and count == 45,
    "create_entity{player_description, control_behavior} sets a real marker")
end

local function ghost_marker(ctx)
  local s = ctx.surface
  local g = s.create_entity{name = "entity-ghost", inner_name = lib.SOCKET, position = {16.5, Y}, direction = lib.E, force = "player"}
  local ok, cb = lib.try(function() return g.get_control_behavior() end)
  lib.log("Q2 ghost get_control_behavior_before ok=" .. tostring(ok) .. " value=" .. tostring(ok and (cb and cb.object_name or "nil") or cb))
  local steps = lib.configure(g, "Ghost block", {{name = lib.SIGNAL, count = 43}})
  lib.log("Q2 ghost configure " .. lib.ser(steps))
  local r = lib.read_cc(g)
  local name, count = lib.live_first_filter(r)
  lib.log("Q2 ghost readback " .. lib.ser(r))
  lib.verdict("Q2 ghost_write", r.desc == "Ghost block" and name == lib.SIGNAL and count == 43,
    "combinator_description and section slots writable on a ghost")

  -- A ghost created with the variant parameters directly.
  local ok2, g2 = lib.try(function()
    return s.create_entity{name = "entity-ghost", inner_name = lib.SOCKET, position = {20.5, Y}, direction = lib.E, force = "player",
      player_description = "Ghost param", control_behavior = lib.bp_cb({{name = lib.SIGNAL, count = 44}})}
  end)
  if ok2 and g2 then
    local r2 = lib.read_cc(g2)
    local n2, c2 = lib.live_first_filter(r2)
    lib.log("Q2 ghost_params readback " .. lib.ser(r2))
    lib.verdict("Q2 ghost_params", r2.desc == "Ghost param" and n2 == lib.SIGNAL and c2 == 44,
      "create_entity{entity-ghost, player_description, control_behavior}")
  else
    lib.log("Q2 ghost_params create ERR " .. tostring(g2))
  end

  -- Capture both ghosts. Does create_blueprint include ghosts, with settings?
  local inv, bp, ents = capture(s, {{15.5, Y - 1}, {21.5, Y + 1}})
  lib.log("Q2 ghost captured count=" .. #ents)
  local by_desc = {}
  for _, be in ipairs(ents) do by_desc[be.player_description or "?"] = be end
  check_be("Q2 capture_ghost", by_desc["Ghost block"], "Ghost block", 43)
  check_be("Q2 capture_ghost_params", by_desc["Ghost param"], "Ghost param", 44)
  inv.destroy()
end

-- The other write path: assigning LuaLogisticSection.filters as a whole.
local function filters_write(ctx)
  local m = ctx.surface.create_entity{name = lib.SOCKET, position = {26.5, Y}, direction = lib.E, force = "player"}
  local cb = m.get_or_create_control_behavior()
  local ok, err = lib.try(function()
    cb.get_section(1).filters = {lib.slot(lib.SIGNAL, 46), lib.slot("signal-A", 3)}
  end)
  local r = lib.read_cc(m)
  local name, count = lib.live_first_filter(r)
  lib.log("Q2 filters_write ok=" .. tostring(ok) .. (ok and "" or (" err=" .. err)), "readback=" .. lib.ser(r))
  lib.verdict("Q2 filters_write", ok and name == lib.SIGNAL and count == 46, "section.filters = {...} on a fresh marker")
end

function q.run(ctx)
  lib.case("Q2 real", function() real_marker(ctx) end)
  lib.case("Q2 filters_write", function() filters_write(ctx) end)
  lib.case("Q2 real_params", function() real_marker_by_params(ctx) end)
  lib.case("Q2 ghost", function() ghost_marker(ctx) end)
end

return q
