-- The instance model under test: stamp, tag and register every ghost, attribute
-- built events by tag, and recount (never decrement) to decide completion.
local lg = require("lg")
local sched = require("sched")
local T = {hooks = {}}

local function key(x, y) return math.floor(x) .. "," .. math.floor(y) end
T.key = key

local function pos_key(name, p) return name .. "@" .. lg.pos(p) end
T.pos_key = pos_key

function T.init()
  storage.inst = {}
  storage.regs = {}
  storage.tile_index = {}
  storage.next_id = 1
end

local function grow(area, box)
  if not area then
    return {{box.left_top.x, box.left_top.y}, {box.right_bottom.x, box.right_bottom.y}}
  end
  area[1][1] = math.min(area[1][1], box.left_top.x)
  area[1][2] = math.min(area[1][2], box.left_top.y)
  area[2][1] = math.max(area[2][1], box.right_bottom.x)
  area[2][2] = math.max(area[2][2], box.right_bottom.y)
  return area
end

local function new_inst(case, surface, force, verbose)
  local id = storage.next_id
  storage.next_id = id + 1
  local inst = {
    id = id, case = case, surface_index = surface.index, force_index = force.index,
    created_tick = game.tick, verbose = verbose, state = "building",
    n_ghosts = 0, n_tiles = 0,
    ghost_refs = {}, ghost_unit = {}, ghost_by_unit = {}, ghost_by_pos = {},
    tile_keys = {}, tile_regs = {}, tile_built = {}, tile_mined = {}, tile_units = {}, tile_refs = {},
    entities = {}, entity_refs = {}, built_tick = {}, built_seq = {}, built_by_pos = {},
    entity_gone = {}, proxies = {},
    built = 0, built_tagged = 0, ghosts_gone = 0, vanished = 0, tiles_built = 0,
    tile_ghosts_gone = 0, entities_gone = 0, tiles_mined = 0,
    delta_hist = {}, order_bad = 0, tile_delta_hist = {}, ghost_gone_tick = {},
    paths = {}, tags_seen = {}, useful_eq_unit = 0, ghost_unit_number_nonnil = 0,
  }
  storage.inst[id] = inst
  return inst
end

local function tag_entity_ghost(inst, g)
  local before = g.tags
  local tags = before or {}
  tags.seb_instance = inst.id
  g.tags = tags
  local reg, useful, ttype = script.register_on_object_destroyed(g)
  storage.regs[reg] = {inst = inst.id, kind = "ghost", unit = g.unit_number, name = g.ghost_name,
    pos = g.position}
  inst.ghost_refs[reg] = g
  inst.ghost_unit[reg] = g.unit_number
  inst.ghost_by_unit[g.unit_number] = reg
  inst.ghost_by_pos[pos_key(g.ghost_name, g.position)] = reg
  inst.n_ghosts = inst.n_ghosts + 1
  if g.ghost_unit_number ~= nil then inst.ghost_unit_number_nonnil = inst.ghost_unit_number_nonnil + 1 end
  if inst.verbose then
    lg.out(string.format(
      "STAMP_GHOST case=%s inst=%d ghost=%s unit=%s ghost_unit_number=%s reg=%s useful=%s type=%s"
      .. " tags_before=%s tags_after=%s item_requests=%s insert_plan=%s",
      inst.case, inst.id, lg.ent(g), tostring(g.unit_number), tostring(g.ghost_unit_number),
      tostring(reg), tostring(useful), tostring(ttype), lg.ser(before), lg.ser(g.tags),
      lg.ser(g.item_requests), lg.ser(g.insert_plan)))
  end
end

local function index_tile(inst, k)
  local idx = storage.tile_index[inst.surface_index] or {}
  storage.tile_index[inst.surface_index] = idx
  idx[k] = inst.id
end

-- Tile ghosts: probe unit_number, tags and registration, all guarded.
local function track_tile_ghost(inst, g, source)
  local k = key(g.position.x, g.position.y)
  if inst.tile_keys[k] then return end
  local ok_u, unit = pcall(function() return g.unit_number end)
  local ok_w, err_w = pcall(function() g.tags = {seb_instance = inst.id} end)
  local ok_r, read = pcall(function() return g.tags end)
  local ok_g, reg, useful, ttype = pcall(script.register_on_object_destroyed, g)
  if ok_g then
    storage.regs[reg] = {inst = inst.id, kind = "tile-ghost", key = k, name = g.ghost_name, pos = g.position}
    inst.tile_regs[k] = reg
  end
  inst.tile_keys[k] = true
  if ok_u and unit then inst.tile_units[unit] = true end
  inst.tile_refs[#inst.tile_refs + 1] = g
  inst.n_tiles = inst.n_tiles + 1
  index_tile(inst, k)
  if inst.verbose then
    lg.out(string.format(
      "STAMP_TILE_GHOST case=%s inst=%d source=%s ghost=%s unit_ok=%s unit=%s tag_write_ok=%s"
      .. " tag_write_err=%s tag_read_ok=%s tag_read=%s reg_ok=%s reg=%s useful=%s type=%s",
      inst.case, inst.id, source, lg.ent(g), tostring(ok_u), tostring(unit), tostring(ok_w),
      tostring(ok_w and "" or err_w), tostring(ok_r), lg.ser(ok_r and read or nil), tostring(ok_g),
      tostring(ok_g and reg or ""), tostring(ok_g and useful or ""), tostring(ok_g and ttype or "")))
  end
end

-- Stamp a blueprint as an instance. opts: verbose, direction, build_mode,
-- tile_search (a radius to look for tile ghosts the return value missed).
function T.stamp(case, stack, surface, position, opts)
  opts = opts or {}
  local force = game.forces.player
  local counts_before = {}
  for k, v in pairs(storage.ev_count) do counts_before[k] = v end
  if opts.verbose then storage.window = "build:" .. case end
  local ok, ghosts = pcall(stack.build_blueprint, {
    surface = surface, force = force, position = position,
    direction = opts.direction or defines.direction.north,
    build_mode = opts.build_mode or defines.build_mode.forced,
    skip_fog_of_war = opts.skip_fog_of_war,
    raise_built = true,
  })
  storage.window = nil
  if not ok then error(ghosts) end
  local raised = {}
  for k, v in pairs(storage.ev_count) do
    if v ~= (counts_before[k] or 0) then raised[k] = v - (counts_before[k] or 0) end
  end
  local inst = new_inst(case, surface, force, opts.verbose)
  inst.stamp_pos = position
  local by_name, area = {}, nil
  for _, g in pairs(ghosts) do
    by_name[g.name] = (by_name[g.name] or 0) + 1
    area = grow(area, g.bounding_box)
  end
  for _, g in pairs(ghosts) do
    if g.name == "entity-ghost" then
      tag_entity_ghost(inst, g)
    elseif g.name == "tile-ghost" then
      track_tile_ghost(inst, g, "returned")
    end
  end
  -- Tile ghosts the return value did not include, found by searching.
  local found_extra = 0
  if opts.tile_search then
    local r = opts.tile_search
    local search = {{position[1] - r, position[2] - r}, {position[1] + r, position[2] + r}}
    for _, g in pairs(surface.find_entities_filtered{area = search, name = "tile-ghost", force = force}) do
      local k = key(g.position.x, g.position.y)
      if not inst.tile_keys[k] and not (storage.tile_index[surface.index] or {})[k] then
        found_extra = found_extra + 1
        area = grow(area, g.bounding_box)
        track_tile_ghost(inst, g, "searched")
      end
    end
  end
  inst.area = area
  lg.out(string.format("STAMP case=%s inst=%d pos=%s returned=%d by_name=%s tile_ghosts_found_by_search=%d"
    .. " area=%s events_raised_during_build=%s",
    case, inst.id, lg.pos(position), #ghosts, lg.ser(by_name), found_extra, lg.ser(area), lg.ser(raised)))
  if opts.verbose then
    storage.verbose_areas = storage.verbose_areas or {}
    local a = area or {{position[1] - 1, position[2] - 1}, {position[1] + 1, position[2] + 1}}
    table.insert(storage.verbose_areas, {surface_index = surface.index, case = case,
      area = {{a[1][1] - 1, a[1][2] - 1}, {a[2][1] + 1, a[2][2] + 1}}})
  end
  T.mark_dirty(inst)
  return inst, ghosts
end

-- Adopt ghosts created some other way (create_entity) as an instance.
function T.adopt(case, surface, ghosts, opts)
  local inst = new_inst(case, surface, game.forces.player, opts and opts.verbose)
  local area
  for _, g in pairs(ghosts) do
    area = grow(area, g.bounding_box)
    if g.name == "entity-ghost" then tag_entity_ghost(inst, g) else track_tile_ghost(inst, g, "adopted") end
  end
  inst.area = area
  if opts and opts.verbose then
    storage.verbose_areas = storage.verbose_areas or {}
    table.insert(storage.verbose_areas, {surface_index = surface.index, case = case,
      area = {{area[1][1] - 1, area[1][2] - 1}, {area[2][1] + 1, area[2][2] + 1}}})
  end
  lg.out(string.format("ADOPT case=%s inst=%d ghosts=%d area=%s", case, inst.id, #ghosts, lg.ser(area)))
  T.mark_dirty(inst)
  return inst
end

-- Counting -------------------------------------------------------------------

function T.count_ghosts(inst, surface)
  local n = 0
  local list = surface.find_entities_filtered{area = inst.area, type = "entity-ghost", force = inst.force_index}
  for _, g in pairs(list) do
    local tags = g.tags
    if tags and tags.seb_instance == inst.id then n = n + 1 end
  end
  return n, #list
end

function T.count_tile_ghosts(inst, surface)
  local n = 0
  local list = surface.find_entities_filtered{area = inst.area, name = "tile-ghost", force = inst.force_index}
  for _, g in pairs(list) do
    if inst.tile_keys[key(g.position.x, g.position.y)] then n = n + 1 end
  end
  return n, #list
end

-- Cheaper filter: tile ghosts turned out to have unit numbers.
function T.count_tile_ghosts_by_unit(inst, surface)
  local n = 0
  local units = inst.tile_units
  local list = surface.find_entities_filtered{area = inst.area, name = "tile-ghost", force = inst.force_index}
  for _, g in pairs(list) do
    if units[g.unit_number] then n = n + 1 end
  end
  return n, #list
end

function T.count_proxies(inst, surface)
  local n = 0
  local list = surface.find_entities_filtered{area = inst.area, type = "item-request-proxy",
    force = inst.force_index}
  for _, p in pairs(list) do
    local target = p.proxy_target
    if target and target.unit_number and inst.entities[target.unit_number] then n = n + 1 end
  end
  return n, #list
end

function T.recount(inst)
  local surface = game.surfaces[inst.surface_index]
  local g = T.count_ghosts(inst, surface)
  local t = T.count_tile_ghosts(inst, surface)
  local p = T.count_proxies(inst, surface)
  return g, t, p
end

function T.mark_dirty(inst)
  if inst.recount_at then return end
  inst.recount_at = game.tick + 3
  sched.at(inst.recount_at, "recount", inst.id)
end

sched.tasks.recount = function(id)
  local inst = storage.inst[id]
  inst.recount_at = nil
  if inst.state ~= "building" then return end
  local g, t, p = T.recount(inst)
  if inst.verbose then
    lg.out(string.format("RECOUNT case=%s inst=%d ghosts=%d tile_ghosts=%d proxies=%d",
      inst.case, id, g, t, p))
  end
  if g == 0 and t == 0 and p == 0 then
    inst.state = "complete"
    inst.complete_tick = game.tick
    lg.out(string.format(
      "COMPLETE case=%s inst=%d after_ticks=%d n_ghosts=%d n_tiles=%d built=%d built_tagged=%d"
      .. " vanished=%d tiles_built=%d ghosts_gone=%d tile_ghosts_gone=%d",
      inst.case, id, game.tick - inst.created_tick, inst.n_ghosts, inst.n_tiles, inst.built,
      inst.built_tagged, inst.vanished, inst.tiles_built, inst.ghosts_gone, inst.tile_ghosts_gone))
    local hook = T.hooks[inst.case]
    if hook then hook(inst) end
  end
end

-- Event intake ---------------------------------------------------------------

function T.on_entity_built(inst, ent, path, tags)
  inst.built = inst.built + 1
  inst.paths[path] = (inst.paths[path] or 0) + 1
  if inst.verbose then inst.tags_seen[ent.unit_number] = tags end
  if tags and tags.seb_instance == inst.id then inst.built_tagged = inst.built_tagged + 1 end
  local unit = ent.unit_number
  local reg_same_unit = inst.ghost_by_unit[unit]
  local reg_same_pos = inst.ghost_by_pos[pos_key(ent.name, ent.position)]
  local ghost = reg_same_pos and inst.ghost_refs[reg_same_pos]
  local ghost_valid = ghost and ghost.valid
  -- A ghost reported destroyed before its built event would be an order problem.
  if reg_same_pos and inst.ghost_gone_tick[reg_same_pos] then
    inst.order_bad = inst.order_bad + 1
    if inst.vanished > 0 then inst.vanished = inst.vanished - 1 end
  end
  local reg, useful = script.register_on_object_destroyed(ent)
  storage.regs[reg] = {inst = inst.id, kind = "entity", unit = unit, name = ent.name, pos = ent.position}
  inst.entities[unit] = reg
  inst.entity_refs[unit] = ent
  inst.built_tick[unit] = game.tick
  inst.built_by_pos[pos_key(ent.name, ent.position)] = unit
  local proxy = ent.item_request_proxy
  local proxy_desc = "nil"
  if proxy then
    local preg = script.register_on_object_destroyed(proxy)
    storage.regs[preg] = {inst = inst.id, kind = "proxy", unit = proxy.unit_number, target = unit,
      built_tick = game.tick}
    inst.proxies[preg] = true
    proxy_desc = lg.ent(proxy) .. " target_is_entity=" .. tostring(proxy.proxy_target == ent)
      .. " requests=" .. lg.ser(proxy.item_requests) .. " preg=" .. preg
  end
  local seq = lg.next_seq()
  inst.built_seq[unit] = seq
  if inst.verbose then
    lg.out(string.format(
      "BUILT path=%s case=%s inst=%d ent=%s unit=%s tags=%s ghost_unit_at_pos=%s same_unit_as_ghost=%s"
      .. " ghost_valid_in_handler=%s ent_reg=%s ent_useful=%s ghost_reg=%s proxy=%s",
      path, inst.case, inst.id, lg.ent(ent), tostring(unit), lg.ser(tags),
      tostring(reg_same_pos and inst.ghost_unit[reg_same_pos]), tostring(reg_same_unit ~= nil),
      tostring(ghost_valid), tostring(reg), tostring(useful), tostring(reg_same_pos), proxy_desc))
  else
    inst.same_unit = (inst.same_unit or 0) + ((reg_same_unit ~= nil) and 1 or 0)
    inst.ghost_valid_in_handler = (inst.ghost_valid_in_handler or 0) + (ghost_valid and 1 or 0)
  end
  T.mark_dirty(inst)
end

function T.on_tiles(surface_index, tiles, path, what)
  local idx = storage.tile_index[surface_index]
  local touched = {}
  for _, t in pairs(tiles) do
    local k = key(t.position.x, t.position.y)
    local id = idx and idx[k]
    local inst = id and storage.inst[id]
    if inst then
      if what == "built" then
        inst.tile_built[k] = game.tick
        inst.tiles_built = inst.tiles_built + 1
      else
        inst.tile_mined[k] = game.tick
        inst.tiles_mined = inst.tiles_mined + 1
      end
      touched[id] = (touched[id] or 0) + 1
    end
  end
  for id, n in pairs(touched) do
    local inst = storage.inst[id]
    if inst.verbose then
      local ps = {}
      for _, t in pairs(tiles) do ps[#ps + 1] = lg.pos(t.position) end
      lg.out(string.format("TILES_%s path=%s case=%s inst=%d n=%d positions=%s old=%s",
        what, path, inst.case, id, n, table.concat(ps, ";"), lg.ser(tiles[1].old_tile and tiles[1].old_tile.name)))
    end
    T.mark_dirty(inst)
    if inst.state == "retiring" then T.check_retired(inst) end
  end
  return touched
end

function T.on_destroyed(inst, r, e)
  local verbose = inst.verbose
  if r.kind == "ghost" then
    inst.ghosts_gone = inst.ghosts_gone + 1
    local unit_built = inst.built_by_pos[pos_key(r.name, r.pos)]
    local matched = unit_built ~= nil
    if not matched then inst.vanished = inst.vanished + 1 end
    local delta = matched and (game.tick - inst.built_tick[unit_built]) or nil
    inst.ghost_gone_tick[e.registration_number] = game.tick
    if e.useful_id == r.unit then inst.useful_eq_unit = inst.useful_eq_unit + 1 end
    if delta then inst.delta_hist[delta] = (inst.delta_hist[delta] or 0) + 1 end
    if verbose then
      lg.out(string.format(
        "DESTROYED kind=ghost case=%s inst=%d reg=%s useful_id=%s ghost_unit=%s useful_is_ghost_unit=%s"
        .. " type=%s built_entity_unit=%s matched_built=%s ticks_after_built=%s",
        inst.case, inst.id, tostring(e.registration_number), tostring(e.useful_id), tostring(r.unit),
        tostring(e.useful_id == r.unit), tostring(e.type), tostring(unit_built), tostring(matched),
        tostring(delta)))
    end
  elseif r.kind == "tile-ghost" then
    inst.tile_ghosts_gone = inst.tile_ghosts_gone + 1
    local bt = inst.tile_built[r.key]
    local delta = bt and (game.tick - bt) or nil
    if delta then inst.tile_delta_hist[delta] = (inst.tile_delta_hist[delta] or 0) + 1 end
    if verbose then
      lg.out(string.format("DESTROYED kind=tile-ghost case=%s inst=%d reg=%s useful_id=%s type=%s tile=%s"
        .. " tile_built_event_seen=%s ticks_after_built=%s",
        inst.case, inst.id, tostring(e.registration_number), tostring(e.useful_id), tostring(e.type),
        r.key, tostring(bt ~= nil), tostring(delta)))
    end
  elseif r.kind == "entity" then
    inst.entities_gone = inst.entities_gone + 1
    inst.entity_gone[r.unit] = game.tick
    if verbose then
      lg.out(string.format("DESTROYED kind=entity case=%s inst=%d reg=%s useful_id=%s unit=%s useful_is_unit=%s"
        .. " name=%s type=%s", inst.case, inst.id, tostring(e.registration_number), tostring(e.useful_id),
        tostring(r.unit), tostring(e.useful_id == r.unit), r.name, tostring(e.type)))
    end
    local hook = T.hooks[inst.case .. ":destroyed"]
    if hook then hook(inst, r, e) end
    if inst.state == "retiring" then T.check_retired(inst) end
  elseif r.kind == "proxy" then
    local target = inst.entity_refs[r.target]
    local modules = target and target.valid and target.get_module_inventory()
    lg.out(string.format("DESTROYED kind=proxy case=%s inst=%d reg=%s useful_id=%s proxy_unit=%s"
      .. " target_unit=%s ticks_after_entity_built=%s target_modules=%s",
      inst.case, inst.id, tostring(e.registration_number), tostring(e.useful_id), tostring(r.unit),
      tostring(r.target), tostring(game.tick - r.built_tick),
      lg.ser(modules and modules.get_contents() or nil)))
    inst.proxy_delivered_tick = game.tick
  elseif r.kind == "tile-proxy" then
    if verbose then
      lg.out(string.format("DESTROYED kind=tile-proxy case=%s inst=%d reg=%s useful_id=%s tile=%s",
        inst.case, inst.id, tostring(e.registration_number), tostring(e.useful_id), tostring(r.key)))
    end
  end
  T.mark_dirty(inst)
end

-- Retirement -------------------------------------------------------------------

function T.retire(inst)
  local surface = game.surfaces[inst.surface_index]
  local force = game.forces[inst.force_index]
  inst.state = "retiring"
  inst.retire_tick = game.tick
  local ent_ok, ent_fail, n_ent = 0, 0, 0
  for unit, e in pairs(inst.entity_refs) do
    if e.valid then
      n_ent = n_ent + 1
      local ok = e.order_deconstruction(force)
      if ok then ent_ok = ent_ok + 1 else ent_fail = ent_fail + 1 end
    end
  end
  inst.retire_entities = n_ent
  local tile_proxies, tile_nil, n_tiles = 0, 0, 0
  local first_ret
  for k in pairs(inst.tile_keys) do
    n_tiles = n_tiles + 1
    local x, y = k:match("^(-?%d+),(-?%d+)$")
    local tile = surface.get_tile(tonumber(x), tonumber(y))
    local proxy = tile.order_deconstruction(force)
    if proxy then
      tile_proxies = tile_proxies + 1
      local preg = script.register_on_object_destroyed(proxy)
      storage.regs[preg] = {inst = inst.id, kind = "tile-proxy", key = k}
      first_ret = first_ret or (lg.ent(proxy) .. " type=" .. proxy.type)
    else
      tile_nil = tile_nil + 1
    end
  end
  inst.retire_tiles = n_tiles
  lg.out(string.format("RETIRE_ORDERED case=%s inst=%d entities=%d order_ok=%d order_false=%d tiles=%d"
    .. " tile_returned_proxy=%d tile_returned_nil=%d first_tile_return=%s",
    inst.case, inst.id, n_ent, ent_ok, ent_fail, n_tiles, tile_proxies, tile_nil, tostring(first_ret)))
end

function T.check_retired(inst)
  if inst.state ~= "retiring" then return end
  local mined = 0
  for k in pairs(inst.tile_keys) do
    if inst.tile_mined[k] then mined = mined + 1 end
  end
  local gone = 0
  for unit in pairs(inst.entities) do
    if inst.entity_gone[unit] then gone = gone + 1 end
  end
  if gone >= inst.retire_entities and mined >= inst.retire_tiles then
    inst.state = "retired"
    lg.out(string.format("RETIRED case=%s inst=%d after_ticks=%d entities_gone=%d tiles_mined=%d",
      inst.case, inst.id, game.tick - inst.retire_tick, gone, mined))
    local hook = T.hooks[inst.case .. ":retired"]
    if hook then hook(inst) end
  end
end

return T
