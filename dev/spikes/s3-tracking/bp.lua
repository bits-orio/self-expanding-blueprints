-- Blueprint designs for each case, built into a temporary script inventory.
local B = {}

-- Returns the inventory (destroy it when done) and the blueprint stack.
function B.new(entities, tiles)
  local inv = game.create_inventory(1)
  local s = inv[1]
  s.set_stack{name = "blueprint"}
  if entities and #entities > 0 then s.set_blueprint_entities(entities) end
  if tiles and #tiles > 0 then s.set_blueprint_tiles(tiles) end
  return inv, s
end

local function ent(n, name, x, y, extra)
  local e = {entity_number = n, name = name, position = {x = x, y = y}}
  for k, v in pairs(extra or {}) do e[k] = v end
  return e
end

local function tile_rect(name, x0, y0, w, h)
  local tiles = {}
  for x = x0, x0 + w - 1 do
    for y = y0, y0 + h - 1 do
      tiles[#tiles + 1] = {name = name, position = {x = x, y = y}}
    end
  end
  return tiles
end

local function module_plan(count)
  local slots = {}
  for i = 0, count - 1 do
    slots[#slots + 1] = {inventory = defines.inventory.crafter_modules, stack = i}
  end
  return {{id = {name = "speed-module"}, items = {in_inventory = slots}}}
end
B.module_plan = module_plan

-- A: robot path. The iron chest carries a blueprint tag of its own, to check
-- that it survives next to seb_instance.
function B.A()
  return {
    ent(1, "wooden-chest", 0.5, 0.5),
    ent(2, "iron-chest", 2.5, 0.5, {tags = {design_tag = "kept"}}),
    ent(3, "small-lamp", 4.5, 0.5),
  }
end

-- S: script revive paths, including an assembler with modules.
function B.S()
  return {
    ent(1, "wooden-chest", 0.5, 0.5),
    ent(2, "iron-chest", 2.5, 0.5),
    ent(3, "small-lamp", 4.5, 0.5),
    ent(4, "assembling-machine-2", 7.5, 1.5, {items = module_plan(2)}),
    ent(5, "small-lamp", 10.5, 0.5),
  }
end

-- T1: tiles only. T2: concrete under an iron chest.
function B.T1() return nil, tile_rect("stone-path", 0, 0, 3, 3) end
function B.T2() return {ent(1, "iron-chest", 0.5, 0.5)}, tile_rect("concrete", 0, 0, 2, 2) end

-- M: assembler with two speed modules.
function B.M() return {ent(1, "assembling-machine-2", 1.5, 1.5, {items = module_plan(2)})} end

-- V: four chests; three will vanish unbuilt.
function B.V()
  return {
    ent(1, "wooden-chest", 0.5, 0.5),
    ent(2, "wooden-chest", 2.5, 0.5),
    ent(3, "wooden-chest", 4.5, 0.5),
    ent(4, "wooden-chest", 6.5, 0.5),
  }
end

-- R: three chests stamped over trees.
function B.R()
  return {
    ent(1, "iron-chest", 0.5, 0.5),
    ent(2, "iron-chest", 2.5, 0.5),
    ent(3, "iron-chest", 4.5, 0.5),
  }
end

-- W: two constant combinators joined by a red wire.
function B.W()
  return {
    ent(1, "constant-combinator", 0.5, 0.5, {wires = {
      {1, defines.wire_connector_id.circuit_red, 2, defines.wire_connector_id.circuit_red},
    }}),
    ent(2, "constant-combinator", 2.5, 0.5),
  }
end

-- C: 10x10 iron chests on 10x10 stone path (100 entity ghosts, 100 tile ghosts).
function B.C()
  local list, n = {}, 0
  for x = 0, 9 do
    for y = 0, 9 do
      n = n + 1
      list[n] = ent(n, "iron-chest", x + 0.5, y + 0.5)
    end
  end
  return list, tile_rect("stone-path", 0, 0, 10, 10)
end

-- D: three chests in a row on stone path, plus a bare row of stone path below.
function B.D()
  return {
    ent(1, "iron-chest", 0.5, 0.5),
    ent(2, "iron-chest", 1.5, 0.5),
    ent(3, "iron-chest", 2.5, 0.5),
  }, tile_rect("stone-path", 0, 0, 3, 2)
end

-- P: platform extension, 3x3 foundation with an iron chest in the middle.
function B.P()
  return {ent(1, "iron-chest", 1.5, 1.5)}, tile_rect("space-platform-foundation", 0, 0, 3, 3)
end

-- One iron chest, no tiles (for stamping onto existing foundation).
function B.chest() return {ent(1, "iron-chest", 0.5, 0.5)} end

-- L: 3x3 landfill with an iron chest in the middle, stamped over water.
function B.L()
  return {ent(1, "iron-chest", 1.5, 1.5)}, tile_rect("landfill", 0, 0, 3, 3)
end

return B
