-- Q9 Signals as data: signal values (a design number, negatives, int32 max, a second section) through
-- create_blueprint, export/import and a stamped ghost. Plus combinator_description length and text
-- fidelity through the same path. Band y=120..124.
local lib = require("lib")
local q = {id = "Q9"}

local Y = 120.5
local VALUES = {
  {name = lib.SIGNAL, count = 42},
  {name = "signal-A", count = -7},
  {name = "signal-B", count = 2147483647},
  {name = "iron-plate", count = 5, type = "item"},
}

-- Capture the marker at pos into a blueprint, round-trip it through a string, stamp it at stamp_pos.
-- Returns the BlueprintEntity after import and the stamped marker ghost.
local function full_path(s, pos, stamp_pos)
  local inv = game.create_inventory(2)
  inv[1].set_stack{name = "blueprint"}
  inv[1].create_blueprint{surface = s, force = "player", area = lib.tile_area(pos)}
  local captured = lib.find_be(inv[1].get_blueprint_entities(), lib.SOCKET)
  local code = inv[2].import_stack(inv[1].export_stack())
  local imported = lib.find_be(inv[2].get_blueprint_entities(), lib.SOCKET)
  local ghost
  for _, g in ipairs(inv[2].build_blueprint{surface = s, force = "player", position = stamp_pos}) do
    if g.valid and g.ghost_name == lib.SOCKET then ghost = g end
  end
  inv.destroy()
  return captured, imported, ghost, code
end

local function bp_values(be)
  local out = {}
  local secs = be and be.control_behavior and be.control_behavior.sections and be.control_behavior.sections.sections or {}
  for _, sec in ipairs(secs) do
    for _, f in ipairs(sec.filters or {}) do out[#out + 1] = sec.index .. ":" .. f.name .. "=" .. f.count end
  end
  return table.concat(out, ",")
end

local function live_values(e)
  local out = {}
  local cb = e and e.get_control_behavior()
  for _, sec in ipairs(cb and cb.sections or {}) do
    for _, f in ipairs(sec.filters) do
      if f.value then out[#out + 1] = sec.index .. ":" .. f.value.name .. "=" .. f.min end
    end
  end
  return table.concat(out, ",")
end

local function signal_values(ctx)
  local s = ctx.surface
  local m = s.create_entity{name = lib.SOCKET, position = {0.5, Y}, direction = lib.E, force = "player"}
  lib.configure(m, "values", VALUES)
  local cb = m.get_control_behavior()
  local sec2 = cb.add_section()
  sec2.set_slot(1, lib.slot(lib.SIGNAL, 7))
  local want = live_values(m)
  lib.log("Q9 live values=" .. want)
  local captured, imported, ghost, code = full_path(s, {x = 0.5, y = Y}, {0.5, Y + 4})
  lib.verdict("Q9 values_captured", bp_values(captured) == want, bp_values(captured))
  lib.verdict("Q9 values_imported", code == 0 and bp_values(imported) == want, bp_values(imported))
  lib.verdict("Q9 values_ghost", ghost ~= nil and live_values(ghost) == want, ghost and live_values(ghost) or "no ghost")
end

-- Lua 5.2 has no utf8 library: count characters (non-continuation bytes) and check that every
-- lead byte is followed by the right number of continuation bytes.
local function utf8_info(str)
  local chars, i, n, valid = 0, 1, #str, true
  while i <= n do
    local b = str:byte(i)
    local len = b < 0x80 and 1 or b >= 0xF0 and 4 or b >= 0xE0 and 3 or b >= 0xC0 and 2 or 0
    if len == 0 or i + len - 1 > n then
      valid = false
      len = 1
    else
      for j = i + 1, i + len - 1 do
        local c = str:byte(j)
        if c < 0x80 or c > 0xBF then valid = false end
      end
    end
    chars = chars + 1
    i = i + len
  end
  return chars, valid
end

local function description_fidelity(ctx)
  local s = ctx.surface
  local texts = {
    {id = "len16", text = string.rep("a", 15) .. "Z"},
    {id = "len256", text = string.rep("a", 255) .. "Z"},
    {id = "len4096", text = string.rep("a", 4095) .. "Z"},
    {id = "len65536", text = string.rep("a", 65535) .. "Z"},
    {id = "len1048576", text = string.rep("a", 1048575) .. "Z"},
    {id = "unicode", text = "Solar block\nzweite Zeile é ✓ [item=iron-plate] \"quoted\""},
    {id = "empty", text = ""},
    {id = "len500", text = string.rep("a", 499) .. "Z"},
    {id = "len501", text = string.rep("a", 500) .. "Z"},
    {id = "utf8_2byte_x300", text = string.rep("é", 300)},
    {id = "utf8_3byte_x200", text = string.rep("✓", 200)},
  }
  for i, t in ipairs(texts) do
    lib.case("Q9 desc " .. t.id, function()
      local x = 8 * i + 0.5
      local m = s.create_entity{name = lib.SOCKET, position = {x, Y}, direction = lib.E, force = "player"}
      m.combinator_description = t.text
      local live = m.combinator_description
      local captured, imported, ghost = full_path(s, {x = x, y = Y}, {x, Y + 4})
      local cap = captured and (captured.player_description or "") or "MISSING"
      local imp = imported and (imported.player_description or "") or "MISSING"
      local gho = ghost and ghost.combinator_description or "MISSING"
      local chars, valid = utf8_info(live)
      lib.log("Q9 desc " .. t.id, "set_bytes=" .. #t.text, "live_bytes=" .. #live, "live_chars=" .. chars,
        "live_valid_utf8=" .. tostring(valid), "captured=" .. #cap, "imported=" .. #imp, "ghost=" .. #gho)
      lib.verdict("Q9 desc " .. t.id, live == t.text and cap == t.text and imp == t.text and gho == t.text,
        "identical text at every stage")
    end)
  end
end

-- Long descriptions written through the blueprint and create_entity paths instead of the live setter.
local function long_description_other_paths(ctx)
  local s = ctx.surface
  local long = string.rep("b", 1999) .. "Z"
  local inv, bp = lib.new_bp({
    {entity_number = 1, name = lib.SOCKET, position = {0.5, 0.5}, direction = lib.E, player_description = long},
  })
  local be = lib.find_be(bp.get_blueprint_entities(), lib.SOCKET)
  local stored = be and be.player_description or ""
  local str = bp.export_stack()
  local inv2 = game.create_inventory(1)
  inv2[1].import_stack(str)
  local imp_be = lib.find_be(inv2[1].get_blueprint_entities(), lib.SOCKET)
  local imported = imp_be and imp_be.player_description or ""
  local ghost
  for _, g in ipairs(bp.build_blueprint{surface = s, force = "player", position = {100.5, Y}}) do
    if g.valid and g.ghost_name == lib.SOCKET then ghost = g end
  end
  local gdesc = ghost and ghost.combinator_description or ""
  local ok, m = lib.try(function()
    return s.create_entity{name = lib.SOCKET, position = {104.5, Y}, direction = lib.E, force = "player", player_description = long}
  end)
  local created = ok and m and m.combinator_description or ""
  lib.log("Q9 long_paths set=" .. #long, "set_blueprint_entities_stored=" .. #stored, "export_import=" .. #imported,
    "stamped_ghost=" .. #gdesc, "create_entity_param=" .. #created)
  inv2.destroy()
  inv.destroy()
end

function q.run(ctx)
  lib.case("Q9 values", function() signal_values(ctx) end)
  lib.case("Q9 desc", function() description_fidelity(ctx) end)
  lib.case("Q9 long_paths", function() long_description_other_paths(ctx) end)
end

return q
