-- Shared helpers for the S2 spike: logging, the test rig, blueprint and marker utilities.
local lib = {}

lib.SOCKET = "seb-spike-socket"
lib.NOWIRE = "seb-spike-socket-nowire"
lib.NOFRG = "seb-spike-socket-nofrg"
lib.TAG = "seb-spike-tagmarker"
lib.SIGNAL = "seb-spike-target"
lib.MARKERS = {[lib.SOCKET] = true, [lib.NOWIRE] = true, [lib.NOFRG] = true, [lib.TAG] = true}

local D = defines.direction
lib.N, lib.E, lib.S, lib.W = D.north, D.east, D.south, D.west

local function clean(s)
  return (tostring(s):gsub("[\r\n]+", " | "))
end
lib.clean = clean

function lib.log(...)
  local parts = {}
  for i = 1, select("#", ...) do
    parts[#parts + 1] = clean(select(i, ...))
  end
  log("SEB_SPIKE " .. table.concat(parts, " "))
end

function lib.ser(v)
  return clean(serpent.line(v, {comment = false, nocode = true, sortkeys = true}))
end

function lib.verdict(id, ok, details)
  lib.log(id, ok and "PASS" or "FAIL", details or "")
end

-- pcall that turns an error into a cleaned string: returns ok, value_or_error
function lib.try(f, ...)
  local ok, res = pcall(f, ...)
  if not ok then return false, clean(res) end
  return true, res
end

function lib.case(id, f)
  local ok, err = pcall(f)
  if not ok then lib.log(id, "CASE_ERROR", clean(err)) end
end

-- The rig: flat lab tiles over [-16, 272)^2 on nauvis, nothing else standing there.
function lib.rig()
  local surface = game.surfaces.nauvis
  surface.request_to_generate_chunks({128, 128}, 7)
  surface.force_generate_chunk_requests()
  local tiles = {}
  for x = -16, 271 do
    for y = -16, 271 do
      tiles[#tiles + 1] = {name = "lab-dark-1", position = {x, y}}
    end
  end
  surface.set_tiles(tiles, false, true, true, false)
  for _, e in pairs(surface.find_entities_filtered{area = {{-16, -16}, {272, 272}}}) do
    if e.valid and e.type ~= "character" then e.destroy() end
  end
  game.forces.enemy.kill_all_units()
  game.map_settings.enemy_expansion.enabled = false
  game.map_settings.pollution.enabled = false
  surface.always_day = true
  return surface
end

function lib.tile_area(p)
  return {{p.x - 0.45, p.y - 0.45}, {p.x + 0.45, p.y + 0.45}}
end

-- A blueprint in its own script inventory. Returns inv, stack. inv.destroy() when done.
function lib.new_bp(entities)
  local inv = game.create_inventory(1)
  inv[1].set_stack{name = "blueprint"}
  if entities then inv[1].set_blueprint_entities(entities) end
  return inv, inv[1]
end

-- BlueprintEntity.control_behavior for a constant combinator with one section.
-- filters: {{name=, count=, type=?}, ...}
function lib.bp_cb(filters)
  local f = {}
  for i, s in ipairs(filters) do
    f[#f + 1] = {index = i, type = s.type or "virtual", name = s.name, quality = "normal", comparator = "=", count = s.count}
  end
  return {sections = {sections = {{index = 1, filters = f}}}}
end

-- LogisticFilter for LuaLogisticSection.set_slot
function lib.slot(name, count, typ)
  return {value = {type = typ or "virtual", name = name, quality = "normal", comparator = "="}, min = count}
end

-- Configure a live (real or ghost) combinator marker: description plus one section of signals.
-- Returns a table of what each step reported.
function lib.configure(e, desc, filters)
  local r = {}
  local ok, err = lib.try(function() e.combinator_description = desc end)
  r.set_desc = ok or err
  local cb
  ok, cb = lib.try(function() return e.get_or_create_control_behavior() end)
  if not ok or not cb then
    r.cb = ok and "nil" or cb
    return r
  end
  r.sections_before = cb.sections_count
  local sec
  ok, sec = lib.try(function() return cb.get_section(1) or cb.add_section() end)
  if not ok or not sec then
    r.section = ok and "nil" or sec
    return r
  end
  for i, s in ipairs(filters or {}) do
    local ok2, res = lib.try(function() return sec.set_slot(i, lib.slot(s.name, s.count, s.type)) end)
    r["slot" .. i] = ok2 and tostring(res) or res
  end
  return r
end

-- Read a combinator marker (real or ghost) through every API this spike cares about.
function lib.read_cc(e)
  local r = {}
  local ok, v = lib.try(function() return e.combinator_description end)
  r.desc = ok and v or ("ERR:" .. v)
  ok, v = lib.try(function()
    local cb = e.get_control_behavior()
    if not cb then return "nil" end
    local out = {obj = cb.object_name, n = cb.sections_count, enabled = cb.enabled, sections = {}}
    for i, s in ipairs(cb.sections) do
      out.sections[i] = {filters = s.filters, group = s.group, active = s.active}
    end
    return out
  end)
  r.cb = ok and v or ("ERR:" .. v)
  return r
end

-- First filter's {name, count} from a BlueprintEntity.control_behavior, or nil.
function lib.bp_first_filter(be)
  local cb = be and be.control_behavior
  local secs = cb and cb.sections and cb.sections.sections
  local f = secs and secs[1] and secs[1].filters and secs[1].filters[1]
  if not f then return nil end
  return f.name, f.count
end

-- First filter's {name, count} from a live control behavior read by lib.read_cc, or nil.
function lib.live_first_filter(read)
  local cb = read and read.cb
  if type(cb) ~= "table" then return nil end
  local s = cb.sections and cb.sections[1]
  local f = s and s.filters and s.filters[1]
  if not f then return nil end
  return f.value and f.value.name, f.min
end

function lib.find_be(entities, name)
  for i, be in ipairs(entities or {}) do
    if be.name == name then return be, i end
  end
end

function lib.ghost_label(g)
  if not g.valid then return "invalid" end
  local n = g.name == "entity-ghost" and ("ghost/" .. g.ghost_name) or g.name
  return string.format("%s@%.1f,%.1f/d%d", n, g.position.x, g.position.y, g.direction)
end

-- Event recorder for script_raised_built and on_blueprint_settings_pasted.
function lib.rec_start(opts)
  storage.rec = {active = true, events = {}, destroy_markers = opts and opts.destroy_markers or false}
end

function lib.rec_stop()
  local rec = storage.rec
  storage.rec = nil
  return rec and rec.events or {}
end

function lib.on_script_raised_built(e)
  local rec = storage.rec
  if not (rec and rec.active) then return end
  local ent = e.entity
  local item = {ev = "built", valid = ent.valid}
  if ent.valid then
    item.name = ent.name
    if ent.name == "entity-ghost" then item.ghost = ent.ghost_name end
    if rec.destroy_markers and item.ghost and lib.MARKERS[item.ghost] then
      ent.destroy()
      item.destroyed_in_handler = true
    end
  end
  rec.events[#rec.events + 1] = item
end

function lib.on_settings_pasted(e)
  local rec = storage.rec
  if not (rec and rec.active) then return end
  local ent = e.entity
  local item = {ev = "pasted", valid = ent.valid, prev_dir = e.previous_direction, tags = e.tags}
  if ent.valid then
    item.name = ent.name
    if ent.name == "entity-ghost" then item.ghost = ent.ghost_name end
    item.dir = ent.direction
  end
  rec.events[#rec.events + 1] = item
end

return lib
