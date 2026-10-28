-- Q6 Direction: create_entity in each direction, the blueprint direction field, and the rotation a
-- stamp applies ((D + d) % 16). Also whether the blueprint records mirroring. Band y=90..100.
local lib = require("lib")
local q = {id = "Q6"}

local function create_dirs(ctx, m, y)
  local s = ctx.surface
  local out = {}
  for i, d in ipairs({0, 2, 4, 8, 12}) do
    local real = s.create_entity{name = m, position = {4 * i + 0.5, y}, direction = d, force = "player"}
    local ghost = s.create_entity{name = "entity-ghost", inner_name = m, position = {4 * i + 2.5, y}, direction = d, force = "player"}
    out[#out + 1] = string.format("d%d->real:%s,ghost:%s", d, tostring(real and real.direction), tostring(ghost and ghost.direction))
    if real then real.destroy() end
    if ghost then ghost.destroy() end
  end
  lib.log("Q6 create_entity marker=" .. m, table.concat(out, " "))
end

local function matrix(ctx, m, y)
  local s = ctx.surface
  local pass, total = 0, 0
  local k = 0
  for _, D in ipairs({"omit", 0, 4, 8, 12}) do
    local ent = {entity_number = 1, name = m, position = {0.5, 0.5}}
    if D ~= "omit" then ent.direction = D end
    local inv, bp = lib.new_bp({ent})
    local stored = bp.get_blueprint_entities()[1].direction
    local row = {}
    for _, d in ipairs({0, 4, 8, 12}) do
      k = k + 1
      local ghosts = bp.build_blueprint{surface = s, force = "player", position = {4 * k + 0.5, y}, direction = d}
      local g = ghosts[1]
      local want = ((D == "omit" and 0 or D) + d) % 16
      local got = g and g.valid and g.direction
      total = total + 1
      if got == want then pass = pass + 1 end
      row[#row + 1] = string.format("d%d:got=%s,want=%d", d, tostring(got), want)
      for _, gg in ipairs(ghosts) do
        if gg.valid then gg.destroy() end
      end
    end
    lib.log("Q6 matrix marker=" .. m, "D=" .. tostring(D), "stored_direction=" .. tostring(stored), table.concat(row, " "))
    inv.destroy()
  end
  lib.verdict("Q6 matrix " .. m, pass == total, pass .. "/" .. total .. " stamps rotate to (D + d) % 16")
end

local function mirror(ctx, m, y)
  local inv, bp = lib.new_bp({{entity_number = 1, name = m, position = {0.5, 0.5}, direction = lib.E, mirror = true}})
  local stored = bp.get_blueprint_entities()[1]
  local ghosts = bp.build_blueprint{surface = ctx.surface, force = "player", position = {100.5, y}}
  local g = ghosts[1]
  local ok, mir = lib.try(function() return g.mirroring end)
  lib.log("Q6 mirror marker=" .. m, "stored_mirror=" .. tostring(stored.mirror), "ghost_mirroring=" .. tostring(ok and mir or mir))
  if g and g.valid then g.destroy() end
  inv.destroy()
end

function q.run(ctx)
  local rows = {{m = lib.SOCKET, y = 90.5}, {m = lib.TAG, y = 96.5}}
  for _, r in ipairs(rows) do
    lib.case("Q6 create " .. r.m, function() create_dirs(ctx, r.m, r.y) end)
    lib.case("Q6 matrix " .. r.m, function() matrix(ctx, r.m, r.y + 2) end)
    lib.case("Q6 mirror " .. r.m, function() mirror(ctx, r.m, r.y + 2) end)
  end
end

return q
