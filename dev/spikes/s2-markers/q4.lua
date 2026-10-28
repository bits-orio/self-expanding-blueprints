-- Q4 Round trips: export_stack/import_stack, a blueprint book, and a hand-written set_blueprint_entities.
-- Band y=70..74.
local lib = require("lib")
local q = {id = "Q4"}

local function marker_fields(be)
  if not be then return "missing" end
  return lib.ser({direction = be.direction, player_description = be.player_description, control_behavior = be.control_behavior})
end

local function compare(id, original, copy)
  local a, b = marker_fields(original), marker_fields(copy)
  lib.log(id, "copy=" .. b)
  lib.verdict(id, a == b and a ~= "missing", "identical direction, player_description, control_behavior")
end

local function export_import(ctx, original)
  local bp = ctx.bp_real[1]
  local str = bp.export_stack()
  local inv = game.create_inventory(1)
  local code = inv[1].import_stack(str)
  lib.log("Q4 export len=" .. #str, "import_code=" .. code)
  compare("Q4 export_import", original, lib.find_be(inv[1].get_blueprint_entities(), lib.SOCKET))
  inv.destroy()
end

local function book(ctx, original)
  local s = ctx.surface
  local inv = game.create_inventory(2)
  inv[1].set_stack{name = "blueprint-book"}
  local binv = inv[1].get_inventory(defines.inventory.item_main)
  local inserted = binv.insert(ctx.bp_real[1])
  local str = inv[1].export_stack()
  local code = inv[2].import_stack(str)
  local binv2 = inv[2].get_inventory(defines.inventory.item_main)
  local inner = binv2 and binv2[1]
  lib.log("Q4 book inserted=" .. inserted, "export len=" .. #str, "import_code=" .. code,
    "inner_is_blueprint=" .. tostring(inner and inner.valid_for_read and inner.is_blueprint))
  if not (inner and inner.valid_for_read) then
    lib.verdict("Q4 book", false, "no blueprint inside the imported book")
    inv.destroy()
    return
  end
  compare("Q4 book", original, lib.find_be(inner.get_blueprint_entities(), lib.SOCKET))
  -- Stamp straight from the book's inner blueprint and read the ghost.
  local ghosts = inner.build_blueprint{surface = s, force = "player", position = {1.5, 70.5}}
  for _, g in ipairs(ghosts) do
    if g.valid and g.ghost_name == lib.SOCKET then
      local r = lib.read_cc(g)
      local n, c = lib.live_first_filter(r)
      lib.verdict("Q4 book_stamp", r.desc == "Solar block" and n == lib.SIGNAL and c == 42, "ghost from book blueprint " .. lib.ser(r))
    end
  end
  inv.destroy()
end

local function hand_written(ctx)
  local s = ctx.surface
  local inv, bp = lib.new_bp({
    {entity_number = 1, name = lib.SOCKET, position = {0.5, 0.5}, direction = lib.S, player_description = "Hand written",
      control_behavior = lib.bp_cb({{name = lib.SIGNAL, count = 99}, {name = "signal-A", count = -5}})},
    {entity_number = 2, name = "wooden-chest", position = {1.5, 0.5}},
  })
  local be = lib.find_be(bp.get_blueprint_entities(), lib.SOCKET)
  local n, c = lib.bp_first_filter(be)
  lib.log("Q4 hand stored=" .. lib.ser(be))
  lib.verdict("Q4 hand_stored", be and be.direction == lib.S and be.player_description == "Hand written" and n == lib.SIGNAL and c == 99,
    "set_blueprint_entities keeps marker settings")
  local ghosts = bp.build_blueprint{surface = s, force = "player", position = {1.5, 74.5}}
  for _, g in ipairs(ghosts) do
    if g.valid and g.ghost_name == lib.SOCKET then
      local r = lib.read_cc(g)
      local n2, c2 = lib.live_first_filter(r)
      lib.log("Q4 hand ghost=" .. lib.ser(r))
      lib.verdict("Q4 hand_stamp", r.desc == "Hand written" and n2 == lib.SIGNAL and c2 == 99 and g.direction == lib.S,
        "ghost stamped from a hand-written blueprint")
    end
  end
  inv.destroy()
end

function q.run(ctx)
  if not ctx.bp_real then
    lib.log("Q4 skipped: no blueprint from Q2")
    return
  end
  local original = lib.find_be(ctx.bp_real[1].get_blueprint_entities(), lib.SOCKET)
  lib.log("Q4 original=" .. marker_fields(original))
  lib.case("Q4 export_import", function() export_import(ctx, original) end)
  lib.case("Q4 book", function() book(ctx, original) end)
  lib.case("Q4 hand", function() hand_written(ctx) end)
end

return q
