-- Q3 Reading back after a stamp: build_blueprint the blueprint captured in Q2 and read the marker ghost
-- through each API separately. Band y=64. Exposes q.probe for the other questions.
local lib = require("lib")
local q = {id = "Q3"}

local Y = 64.5

-- Log every API call on a marker ghost on its own line: which ones work on a ghost.
function q.probe(tag, g)
  local function call(label, f)
    local ok, v = lib.try(f)
    lib.log(tag, "api=" .. label, "ok=" .. tostring(ok), "value=" .. (ok and lib.ser(v) or v))
    return ok, v
  end
  call("name/ghost_name/ghost_type", function() return {g.name, g.ghost_name, g.ghost_type} end)
  call("direction", function() return g.direction end)
  call("position", function() return g.position end)
  call("combinator_description", function() return g.combinator_description end)
  local okcb, cb = call("get_control_behavior().object_name", function()
    local c = g.get_control_behavior()
    return c and c.object_name or "nil"
  end)
  call("get_or_create_control_behavior().object_name", function() return g.get_or_create_control_behavior().object_name end)
  call("cb.enabled", function() return g.get_control_behavior().enabled end)
  call("cb.sections_count", function() return g.get_control_behavior().sections_count end)
  call("cb.get_section(1).filters", function() return g.get_control_behavior().get_section(1).filters end)
  call("cb.get_section(1).get_slot(1)", function() return g.get_control_behavior().get_section(1).get_slot(1) end)
  call("cb.get_section(1).is_manual/active/multiplier/group", function()
    local s = g.get_control_behavior().get_section(1)
    return {s.is_manual, s.active, s.multiplier, s.group}
  end)
  call("#cb.sections", function() return #g.get_control_behavior().sections end)
  call("tags", function() return g.tags end)
  call("ghost_prototype.items_to_place_this", function() return g.ghost_prototype.items_to_place_this end)
  call("supports_direction", function() return g.supports_direction end)
  call("mirroring", function() return g.mirroring end)
  return okcb
end

function q.run(ctx)
  lib.case("Q3 stamp", function()
    local s = ctx.surface
    local bp = ctx.bp_real[1]
    local ghosts = bp.build_blueprint{surface = s, force = "player", position = {1.5, Y}, build_mode = defines.build_mode.normal}
    local labels = {}
    local marker
    for _, g in ipairs(ghosts) do
      labels[#labels + 1] = lib.ghost_label(g)
      if g.valid and g.name == "entity-ghost" and g.ghost_name == lib.SOCKET then marker = g end
    end
    lib.log("Q3 stamp returned=" .. #ghosts, "[" .. table.concat(labels, ";") .. "]")
    if not marker then
      lib.verdict("Q3 readback", false, "no marker ghost returned")
      return
    end
    q.probe("Q3 probe", marker)
    local r = lib.read_cc(marker)
    local name, count = lib.live_first_filter(r)
    lib.verdict("Q3 readback", r.desc == "Solar block" and name == lib.SIGNAL and count == 42 and marker.direction == lib.E,
      string.format("desc=%s filter=%s/%s dir=%d", tostring(r.desc), tostring(name), tostring(count), marker.direction))

    -- Writing to a stamped ghost, then reading back.
    local w = lib.configure(marker, "rewritten", {{name = lib.SIGNAL, count = 77}})
    local r2 = lib.read_cc(marker)
    local n2, c2 = lib.live_first_filter(r2)
    lib.log("Q3 rewrite configure=" .. lib.ser(w))
    lib.verdict("Q3 rewrite_ghost", r2.desc == "rewritten" and n2 == lib.SIGNAL and c2 == 77, "stamped ghost settings writable")

    -- Section management and the on/off flag on a ghost.
    local cb = marker.get_control_behavior()
    local ok_add, sec2 = lib.try(function() return cb.add_section() end)
    local after_add = cb.sections_count
    local ok_rm, removed = lib.try(function() return cb.remove_section(2) end)
    local after_rm = cb.sections_count
    local ok_en = lib.try(function() cb.enabled = false end)
    lib.log("Q3 ghost_sections add ok=" .. tostring(ok_add) .. " got=" .. tostring(ok_add and sec2 and sec2.object_name),
      "count_after_add=" .. after_add, "remove ok=" .. tostring(ok_rm) .. " result=" .. tostring(removed), "count_after_remove=" .. after_rm,
      "set_enabled ok=" .. tostring(ok_en), "enabled_now=" .. tostring(cb.enabled))
    ctx.q3_marker = marker
  end)
end

return q
