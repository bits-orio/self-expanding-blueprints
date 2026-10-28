-- Script-inventory blueprints: create from a spec, stamp, collect ghosts, clean up.
local fmt = require("lib.fmt")
local B = {}

local GHOST_TYPES = {"entity-ghost", "tile-ghost"}

local function copy_entity(e, i)
  local c = {}
  for k, v in pairs(e) do c[k] = v end
  c.position = {x = e.position.x, y = e.position.y}
  c.entity_number = i
  c.tags = {i = i}
  return c
end

-- Re-read what the blueprint actually stores (positions may be fixed up).
function B.read(bp)
  bp.ents = {}
  bp.ent_list = {}
  for _, e in pairs(bp.stack.get_blueprint_entities() or {}) do
    local i = (e.tags and e.tags.i) or e.entity_number
    bp.ents[i] = e
    bp.ent_list[#bp.ent_list + 1] = e
  end
  bp.tiles = bp.stack.get_blueprint_tiles() or {}
  return bp
end

function B.new(spec)
  local inv = game.create_inventory(1)
  local s = inv[1]
  s.set_stack({name = "blueprint"})
  local ents = {}
  for i, e in ipairs(spec.entities or {}) do ents[i] = copy_entity(e, i) end
  if #ents > 0 then
    if spec.fix_positions == nil then s.set_blueprint_entities(ents)
    else s.set_blueprint_entities(ents, spec.fix_positions) end
  end
  if spec.tiles and #spec.tiles > 0 then s.set_blueprint_tiles(spec.tiles) end
  if spec.snap then s.blueprint_snap_to_grid = spec.snap end
  if spec.absolute ~= nil then s.blueprint_absolute_snapping = spec.absolute end
  if spec.rel then s.blueprint_position_relative_to_grid = spec.rel end
  local bp = B.read({id = spec.id, inv = inv, stack = s, spec = spec})
  return bp
end

-- Wrap an already set-up blueprint stack (e.g. from create_blueprint).
function B.wrap(id, inv)
  local s = inv[1]
  for _, e in pairs(s.get_blueprint_entities() or {}) do
    s.set_blueprint_entity_tags(e.entity_number, {i = e.entity_number})
  end
  return B.read({id = id, inv = inv, stack = s, spec = {id = id}})
end

-- Re-create a blueprint from an export string (keeps the i tags).
function B.from_export(id, str)
  local inv = game.create_inventory(1)
  local result = inv[1].import_stack(str)
  local bp = B.read({id = id, inv = inv, stack = inv[1], spec = {id = id}})
  bp.import_result = result
  return bp
end

-- Log stored positions that differ from the spec (fix_positions effects).
function B.report_fixups(bp)
  local moved = {}
  for i, e in ipairs(bp.spec.entities or {}) do
    local st = bp.ents[i]
    if not st then
      moved[#moved + 1] = i .. ":" .. e.name .. ":DROPPED"
    elseif st.position.x ~= e.position.x or st.position.y ~= e.position.y then
      moved[#moved + 1] = i .. ":" .. e.name .. ":" .. fmt.p(e.position) .. "->" .. fmt.p(st.position)
    end
  end
  return moved
end

function B.area(P, r)
  return {{P.x - r, P.y - r}, {P.x + r, P.y + r}}
end

function B.clear(surface, P, r)
  for _, g in pairs(surface.find_entities_filtered({area = B.area(P, r or 48), type = GHOST_TYPES})) do
    if g.valid then g.destroy() end
  end
end

-- Stamp once and describe every ghost in range. opts: mode, raise_built, force,
-- radius, keep (do not clear afterwards), skip_fog.
function B.stamp(bp, surface, P, d, opts)
  opts = opts or {}
  local args = {
    surface = surface,
    force = opts.force or "player",
    position = P,
    direction = d,
    build_mode = opts.mode or defines.build_mode.forced,
    raise_built = opts.raise_built ~= false,
    skip_fog_of_war = opts.skip_fog or false,
  }
  if opts.omit_skip_fog then args.skip_fog_of_war = nil end
  local ret = bp.stack.build_blueprint(args)
  local r = opts.radius or 48
  local found = surface.find_entities_filtered({area = B.area(P, r), type = GHOST_TYPES})
  local rec = {P = P, d = d, n_ret = #ret, n_found = #found, ghosts = {}, ret_e = 0, ret_t = 0, order = {}}
  for _, g in pairs(ret) do
    if g.valid and g.type == "tile-ghost" then rec.ret_t = rec.ret_t + 1 else rec.ret_e = rec.ret_e + 1 end
    if g.valid and g.type == "entity-ghost" then
      rec.order[#rec.order + 1] = (g.tags and g.tags.i) or "?"
    elseif g.valid then
      rec.order[#rec.order + 1] = "t"
    end
  end
  for _, g in pairs(found) do
    local in_ret = false
    for _, h in pairs(ret) do
      if h.valid and h == g then in_ret = true break end
    end
    local tags = g.type == "entity-ghost" and g.tags or nil
    rec.ghosts[#rec.ghosts + 1] = {
      kind = g.type == "tile-ghost" and "t" or "e",
      i = tags and tags.i or nil,
      name = g.ghost_name,
      pos = {x = g.position.x, y = g.position.y},
      dir = g.direction,
      in_ret = in_ret,
    }
  end
  if not opts.keep then B.clear(surface, P, r) end
  return rec
end

local function key_of(g)
  if g.kind == "t" then return "t:" .. g.name end
  return "e" .. tostring(g.i) .. ":" .. g.name
end

-- Offsets from P, as a canonical string.
function B.sig(rec)
  local keys = {}
  for _, g in pairs(rec.ghosts) do
    keys[#keys + 1] = key_of(g) .. "=" .. fmt.p({x = g.pos.x - rec.P.x, y = g.pos.y - rec.P.y}) .. "/" .. g.dir
  end
  table.sort(keys)
  return table.concat(keys, ";")
end

-- Absolute positions shifted by -t, as a canonical string.
function B.shifted_sig(rec, t)
  local keys = {}
  for _, g in pairs(rec.ghosts) do
    keys[#keys + 1] = key_of(g) .. "=" .. fmt.p({x = g.pos.x - t.x, y = g.pos.y - t.y}) .. "/" .. g.dir
  end
  table.sort(keys)
  return table.concat(keys, ";")
end

function B.min_pos(rec)
  local best
  for _, g in pairs(rec.ghosts) do
    if not best or g.pos.x < best.x or (g.pos.x == best.x and g.pos.y < best.y) then
      best = {x = g.pos.x, y = g.pos.y}
    end
  end
  return best
end

function B.expected_count(bp)
  return #bp.ent_list + #bp.tiles
end

return B
