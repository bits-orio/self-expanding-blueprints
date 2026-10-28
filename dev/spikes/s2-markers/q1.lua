-- Q1 Placement: can markers (real and ghost) go over entities, other markers and water?
-- Bands (each target uses y, y+4, y+8): socket y=0.5, tag marker y=16.5, nofrg socket y=32.5 (cc target
-- only), stacking y=48.5.
local lib = require("lib")
local q = {id = "Q1"}

local BCTS = {"script", "manual", "manual_ghost", "script_ghost", "blueprint_ghost", "ghost_revive"}
local TARGETS = {
  "empty", "chest", "belt", "am1_center", "am1_corner", "socket_real_N", "socket_real_E",
  "socket_ghost_E", "tag_real", "cc_real", "water", "tree",
}

local function setup(surface, kind, p)
  local f = "player"
  if kind == "chest" then
    return surface.create_entity{name = "wooden-chest", position = p, force = f}
  elseif kind == "belt" then
    return surface.create_entity{name = "transport-belt", position = p, force = f, direction = lib.E}
  elseif kind == "am1_center" then
    return surface.create_entity{name = "assembling-machine-1", position = p, force = f}
  elseif kind == "am1_corner" then
    return surface.create_entity{name = "assembling-machine-1", position = {p.x + 1, p.y + 1}, force = f}
  elseif kind == "socket_real_N" or kind == "socket_real_E" then
    local dir = kind == "socket_real_N" and lib.N or lib.E
    local e = surface.create_entity{name = lib.SOCKET, position = p, force = f, direction = dir}
    e.combinator_description = "pre-existing"
    return e
  elseif kind == "socket_ghost_E" then
    local e = surface.create_entity{name = "entity-ghost", inner_name = lib.SOCKET, position = p, force = f, direction = lib.E}
    pcall(function() e.combinator_description = "pre-existing" end)
    return e
  elseif kind == "tag_real" then
    return surface.create_entity{name = lib.TAG, position = p, force = f, direction = lib.E}
  elseif kind == "cc_real" then
    return surface.create_entity{name = "constant-combinator", position = p, force = f, direction = lib.E}
  elseif kind == "water" then
    local tiles = {}
    for dx = -1, 1 do
      for dy = -1, 1 do
        tiles[#tiles + 1] = {name = "water", position = {math.floor(p.x) + dx, math.floor(p.y) + dy}}
      end
    end
    surface.set_tiles(tiles, false)
    return nil
  elseif kind == "tree" then
    return surface.create_entity{name = "tree-01", position = p}
  end
end

local function pre_state(pre)
  if not pre then return "none" end
  if not pre.valid then return "INVALID" end
  local s = pre.name == "entity-ghost" and ("ghost/" .. pre.ghost_name) or pre.name
  s = s .. "/d" .. pre.direction
  local ok, desc = lib.try(function() return pre.combinator_description end)
  if ok then s = s .. "/desc=" .. desc end
  if pre.to_be_deconstructed() then s = s .. "/decon" end
  if pre.to_be_upgraded() then s = s .. "/upgrade" end
  return s
end

local function counts(surface, p, name)
  local a = lib.tile_area(p)
  return surface.count_entities_filtered{area = a, name = name}, surface.count_entities_filtered{area = a, ghost_name = name}
end

local function canplace(surface, kind, m, p)
  for _, as in ipairs({"entity", "ghost"}) do
    local out = {}
    for _, b in ipairs(BCTS) do
      local ok, v = lib.try(function()
        local args = {name = m, position = p, direction = lib.E, force = "player", build_check_type = defines.build_check_type[b]}
        if as == "ghost" then
          args.name = "entity-ghost"
          args.inner_name = m
        end
        return surface.can_place_entity(args)
      end)
      out[#out + 1] = b .. "=" .. (ok and tostring(v) or ("ERR(" .. v .. ")"))
    end
    lib.log("Q1 canplace target=" .. kind, "marker=" .. m, "as=" .. as, table.concat(out, " "))
  end
end

local function create(surface, kind, m, p, pre)
  for _, as in ipairs({"entity", "ghost"}) do
    local r0, g0 = counts(surface, p, m)
    local ok, e = lib.try(function()
      if as == "ghost" then
        return surface.create_entity{name = "entity-ghost", inner_name = m, position = p, direction = lib.E, force = "player"}
      end
      return surface.create_entity{name = m, position = p, direction = lib.E, force = "player"}
    end)
    local r1, g1 = counts(surface, p, m)
    lib.log("Q1 create target=" .. kind, "marker=" .. m, "as=" .. as, "ok=" .. tostring(ok),
      "created=" .. tostring(ok and e ~= nil), "real " .. r0 .. "->" .. r1, "ghost " .. g0 .. "->" .. g1,
      "pre=" .. pre_state(pre), ok and "" or ("err=" .. e))
    if ok and e and e.valid then e.destroy() end
  end
end

local function stamp(surface, kind, m, p, pre, mode)
  local ent = {entity_number = 1, name = m, position = {0.5, 0.5}, direction = lib.E}
  if m ~= lib.TAG then ent.player_description = "from-bp" end
  local inv, bp = lib.new_bp({ent})
  lib.rec_start()
  local ok, ghosts = lib.try(function()
    return bp.build_blueprint{surface = surface, force = "player", position = p, build_mode = defines.build_mode[mode], raise_built = true}
  end)
  local events = lib.rec_stop()
  local labels = {}
  if ok then
    for _, g in ipairs(ghosts) do labels[#labels + 1] = lib.ghost_label(g) end
  end
  local r1, g1 = counts(surface, p, m)
  lib.log("Q1 stamp target=" .. kind, "marker=" .. m, "mode=" .. mode, "ok=" .. tostring(ok),
    "returned=" .. (ok and #ghosts or ("ERR:" .. ghosts)), "ghosts=[" .. table.concat(labels, ";") .. "]",
    "at_tile real=" .. r1 .. " ghost=" .. g1, "pre=" .. pre_state(pre), "events=" .. lib.ser(events))
  if ok then
    for _, g in ipairs(ghosts) do
      if g.valid then g.destroy() end
    end
  end
  inv.destroy()
end

-- Each sub-test gets its own freshly set-up copy of the target, 4 tiles further down.
local function run_target(surface, kind, m, p)
  local function at(j) return {x = p.x, y = p.y + 4 * j} end
  local p0 = at(0)
  local pre = setup(surface, kind, p0)
  canplace(surface, kind, m, p0)
  create(surface, kind, m, p0, pre)
  local p1 = at(1)
  pre = setup(surface, kind, p1)
  stamp(surface, kind, m, p1, pre, "normal")
  local p2 = at(2)
  pre = setup(surface, kind, p2)
  stamp(surface, kind, m, p2, pre, "forced")
end

-- Two markers on one tile, inside one blueprint and in the world.
local function stacking(surface)
  local y = 48.5
  local cases = {
    {id = "same_name_diff_dir", ents = {{lib.SOCKET, lib.N, "A"}, {lib.SOCKET, lib.E, "B"}}},
    {id = "same_name_same_dir", ents = {{lib.SOCKET, lib.E, "A"}, {lib.SOCKET, lib.E, "B"}}},
    {id = "socket_plus_nowire", ents = {{lib.SOCKET, lib.E, "A"}, {lib.NOWIRE, lib.E, "B"}}},
    {id = "socket_plus_tag", ents = {{lib.SOCKET, lib.E, "A"}, {lib.TAG, lib.E}}},
  }
  for i, c in ipairs(cases) do
    local p = {x = 8 * i + 0.5, y = y}
    local ents = {}
    for n, spec in ipairs(c.ents) do
      ents[n] = {entity_number = n, name = spec[1], position = {0.5, 0.5}, direction = spec[2], player_description = spec[3]}
    end
    local inv, bp = lib.new_bp(ents)
    local stored = bp.get_blueprint_entity_count()
    lib.rec_start()
    local ok, ghosts = lib.try(function()
      return bp.build_blueprint{surface = surface, force = "player", position = p, build_mode = defines.build_mode.normal, raise_built = true}
    end)
    local events = lib.rec_stop()
    local labels = {}
    if ok then
      for _, g in ipairs(ghosts) do labels[#labels + 1] = lib.ghost_label(g) end
    end
    local at = surface.count_entities_filtered{area = lib.tile_area(p), type = "entity-ghost"}
    lib.log("Q1 stack_bp case=" .. c.id, "stored=" .. stored, "returned=" .. (ok and #ghosts or ("ERR:" .. ghosts)),
      "ghosts=[" .. table.concat(labels, ";") .. "]", "ghosts_at_tile=" .. at, "events=" .. lib.ser(events))
    lib.verdict("Q1 stack_bp " .. c.id, ok and #ghosts == #c.ents and at == #c.ents, "want " .. #c.ents .. " marker ghosts on the tile")
    inv.destroy()
  end
  -- World: two real socket markers on one tile, then create_blueprint over that tile.
  local p = {x = 48.5, y = y}
  local a = surface.create_entity{name = lib.SOCKET, position = p, direction = lib.N, force = "player"}
  local b = surface.create_entity{name = lib.SOCKET, position = p, direction = lib.E, force = "player"}
  local n_world = surface.count_entities_filtered{area = lib.tile_area(p), name = lib.SOCKET}
  local inv, bp = lib.new_bp()
  bp.create_blueprint{surface = surface, force = "player", area = lib.tile_area(p)}
  local ents = bp.get_blueprint_entities() or {}
  local dirs = {}
  for _, be in ipairs(ents) do dirs[#dirs + 1] = be.name .. "/d" .. tostring(be.direction) end
  lib.log("Q1 stack_world created_a=" .. tostring(a ~= nil), "created_b=" .. tostring(b ~= nil), "in_world=" .. n_world,
    "captured=" .. #ents, "[" .. table.concat(dirs, ";") .. "]")
  lib.verdict("Q1 stack_world", n_world == 2 and #ents == 2, "two stacked real markers both captured")
  inv.destroy()
end

function q.run(ctx)
  local s = ctx.surface
  local rows = {{m = lib.SOCKET, y = 0.5}, {m = lib.TAG, y = 16.5}}
  for _, row in ipairs(rows) do
    for i, kind in ipairs(TARGETS) do
      lib.case("Q1 " .. kind .. " " .. row.m, function()
        run_target(s, kind, row.m, {x = 8 * i + 0.5, y = row.y})
      end)
    end
  end
  lib.case("Q1 cc_real nofrg", function()
    run_target(s, "cc_real", lib.NOFRG, {x = 8.5, y = 32.5})
  end)
  lib.case("Q1 stacking", function() stacking(s) end)
end

return q
