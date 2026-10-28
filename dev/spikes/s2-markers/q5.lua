-- Q5 Tags baseline for the simple-entity-with-owner marker: blueprint entity tags through build_blueprint,
-- export/import and a book; plus what create_blueprint captures from real and ghost tag markers, and
-- whether the combinator marker can carry tags too (a hybrid). Band y=80..84.
local lib = require("lib")
local q = {id = "Q5"}

local Y = 80.5
local TAGS = {seb_target = "Solar block", seb_design = 42, nested = {a = 1, list = {1, 2}}}

local function tag_bp()
  local inv, bp = lib.new_bp({
    {entity_number = 1, name = lib.TAG, position = {0.5, 0.5}, direction = lib.E},
    {entity_number = 2, name = "wooden-chest", position = {1.5, 0.5}},
  })
  local _, idx = lib.find_be(bp.get_blueprint_entities(), lib.TAG)
  bp.set_blueprint_entity_tags(idx, TAGS)
  return inv, bp, idx
end

local function same(a, b) return lib.ser(a) == lib.ser(b) end

local function stamped_marker_tags(surface, bp, pos, name)
  local ghosts = bp.build_blueprint{surface = surface, force = "player", position = pos}
  for _, g in ipairs(ghosts) do
    if g.valid and g.ghost_name == name then return g.tags, g end
  end
end

local function tags_through_stamp(ctx)
  local inv, bp, idx = tag_bp()
  local stored = bp.get_blueprint_entity_tags(idx)
  local be = lib.find_be(bp.get_blueprint_entities(), lib.TAG)
  lib.log("Q5 stored index=" .. idx, "get_blueprint_entity_tags=" .. lib.ser(stored), "entity.tags=" .. lib.ser(be and be.tags))
  local tags = stamped_marker_tags(ctx.surface, bp, {1.5, Y}, lib.TAG)
  lib.verdict("Q5 stamp_tags", same(tags, TAGS), "ghost.tags=" .. lib.ser(tags))

  local str = bp.export_stack()
  local inv2 = game.create_inventory(2)
  local code = inv2[1].import_stack(str)
  local _, idx2 = lib.find_be(inv2[1].get_blueprint_entities(), lib.TAG)
  local t2 = idx2 and inv2[1].get_blueprint_entity_tags(idx2)
  lib.verdict("Q5 export_import_tags", code == 0 and same(t2, TAGS), "import_code=" .. code .. " tags=" .. lib.ser(t2))

  inv2[2].set_stack{name = "blueprint-book"}
  local binv = inv2[2].get_inventory(defines.inventory.item_main)
  binv.insert(bp)
  local bstr = inv2[2].export_stack()
  inv2[2].clear()
  inv2[2].import_stack(bstr)
  local inner = inv2[2].get_inventory(defines.inventory.item_main)[1]
  local _, idx3 = lib.find_be(inner.get_blueprint_entities(), lib.TAG)
  local t3 = idx3 and inner.get_blueprint_entity_tags(idx3)
  lib.verdict("Q5 book_tags", same(t3, TAGS), "tags=" .. lib.ser(t3))
  inv2.destroy()
  inv.destroy()
end

local function tags_in_entity_table(ctx)
  local inv, bp = lib.new_bp({
    {entity_number = 1, name = lib.TAG, position = {0.5, 0.5}, direction = lib.E, tags = TAGS},
  })
  local be = lib.find_be(bp.get_blueprint_entities(), lib.TAG)
  local tags = stamped_marker_tags(ctx.surface, bp, {8.5, Y}, lib.TAG)
  lib.verdict("Q5 entity_table_tags", be and same(be.tags, TAGS) and same(tags, TAGS),
    "stored=" .. lib.ser(be and be.tags) .. " ghost=" .. lib.ser(tags))
  inv.destroy()
end

-- What create_blueprint takes from the world: a real tag marker (no tags possible) and a ghost with tags.
local function capture_from_world(ctx)
  local s = ctx.surface
  local real = s.create_entity{name = lib.TAG, position = {16.5, Y}, direction = lib.E, force = "player"}
  local ok, rt = lib.try(function() return real.tags end)
  local okw, werr = lib.try(function() real.tags = TAGS end)
  local okr, after = lib.try(function() return real.tags end)
  lib.log("Q5 real_tag_marker read_tags ok=" .. tostring(ok) .. " value=" .. (ok and lib.ser(rt) or rt),
    "write_tags ok=" .. tostring(okw) .. (okw and "" or (" err=" .. werr)),
    "read_after_write=" .. (okr and lib.ser(after) or after))
  lib.verdict("Q5 real_entity_holds_tags", okr and lib.ser(after) == lib.ser(TAGS), "a real (non-ghost) marker keeps written tags")
  local ghost = s.create_entity{name = "entity-ghost", inner_name = lib.TAG, position = {18.5, Y}, direction = lib.E, force = "player", tags = TAGS}
  lib.log("Q5 ghost_tag_marker tags=" .. lib.ser(ghost.tags))
  local inv, bp = lib.new_bp()
  bp.create_blueprint{surface = s, force = "player", area = {{15.5, Y - 1}, {19.5, Y + 1}}}
  local ents = bp.get_blueprint_entities() or {}
  for i, be in ipairs(ents) do
    lib.log("Q5 captured i=" .. i, "name=" .. be.name, "x=" .. be.position.x, "tags=" .. lib.ser(be.tags),
      "entity_tags=" .. lib.ser(bp.get_blueprint_entity_tags(i)))
  end
  inv.destroy()
end

-- Hybrid: blueprint entity tags on the combinator marker as well.
local function hybrid(ctx)
  local inv, bp = lib.new_bp({
    {entity_number = 1, name = lib.SOCKET, position = {0.5, 0.5}, direction = lib.E, player_description = "Hybrid"},
  })
  bp.set_blueprint_entity_tags(1, TAGS)
  local tags, g = stamped_marker_tags(ctx.surface, bp, {24.5, Y}, lib.SOCKET)
  local desc = g and lib.read_cc(g).desc
  lib.verdict("Q5 hybrid_socket_tags", same(tags, TAGS) and desc == "Hybrid", "ghost.tags=" .. lib.ser(tags) .. " desc=" .. tostring(desc))
  inv.destroy()
end

-- A tagged tag-marker stamped over a real tag marker (same name and direction): no ghost is made, so
-- do the tags reach the mod through on_blueprint_settings_pasted?
local function paste_over_real(ctx)
  local s = ctx.surface
  local pos = {x = 32.5, y = Y}
  local real = s.create_entity{name = lib.TAG, position = pos, direction = lib.E, force = "player"}
  local inv, bp = lib.new_bp({{entity_number = 1, name = lib.TAG, position = {0.5, 0.5}, direction = lib.E, tags = TAGS}})
  lib.rec_start()
  local ghosts = bp.build_blueprint{surface = s, force = "player", position = pos, raise_built = true}
  local events = lib.rec_stop()
  local pasted
  for _, ev in ipairs(events) do
    if ev.ev == "pasted" then pasted = ev end
  end
  lib.log("Q5 paste_over_real returned=" .. #ghosts, "events=" .. lib.ser(events))
  lib.verdict("Q5 paste_over_real_tags", #ghosts == 0 and pasted ~= nil and same(pasted.tags, TAGS) and real.valid,
    "no ghost; on_blueprint_settings_pasted carries the blueprint tags for the real marker")
  inv.destroy()

  -- Same over an existing tag-marker GHOST that holds old tags: are the ghost's tags replaced?
  local gpos = {x = 36.5, y = Y}
  local old = s.create_entity{name = "entity-ghost", inner_name = lib.TAG, position = gpos, direction = lib.E, force = "player",
    tags = {seb_target = "old"}}
  local inv2, bp2 = lib.new_bp({{entity_number = 1, name = lib.TAG, position = {0.5, 0.5}, direction = lib.E, tags = TAGS}})
  lib.rec_start()
  local ghosts2 = bp2.build_blueprint{surface = s, force = "player", position = gpos, raise_built = true}
  local events2 = lib.rec_stop()
  lib.log("Q5 paste_over_ghost returned=" .. #ghosts2, "events=" .. lib.ser(events2), "old_ghost_valid=" .. tostring(old.valid),
    "old_ghost_tags_after=" .. lib.ser(old.valid and old.tags))
  lib.verdict("Q5 paste_over_ghost_tags", #ghosts2 == 0 and old.valid and same(old.tags, TAGS),
    "existing ghost kept, its tags replaced by the blueprint's")
  inv2.destroy()
end

function q.run(ctx)
  lib.case("Q5 stamp", function() tags_through_stamp(ctx) end)
  lib.case("Q5 paste_over_real", function() paste_over_real(ctx) end)
  lib.case("Q5 entity_table", function() tags_in_entity_table(ctx) end)
  lib.case("Q5 world", function() capture_from_world(ctx) end)
  lib.case("Q5 hybrid", function() hybrid(ctx) end)
end

return q
