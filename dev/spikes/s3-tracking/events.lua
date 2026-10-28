-- Event wiring. Every event in defines.events gets a handler, so anything the
-- engine raises near a verbose case, or during a scripted "window" (a revive
-- or destroy call), is logged even if nothing here expected it.
local lg = require("lg")
local track = require("track")
local E = {}

local SKIP = {
  on_tick = true, on_chunk_generated = true, on_chunk_charted = true, on_sector_scanned = true,
}

local function entity_of(e)
  return e.entity or e.ghost or e.created_entity or e.destination or e.source
end

local function in_area(va, si, x, y)
  local a = va.area
  return va.surface_index == si and x >= a[1][1] and x <= a[2][1] and y >= a[1][2] and y <= a[2][2]
end

local function verbose_case(ent)
  if not (ent and ent.valid) then return nil end
  local p, si = ent.position, ent.surface.index
  for _, va in pairs(storage.verbose_areas or {}) do
    if in_area(va, si, p.x, p.y) then return va.case end
  end
end

local function tiles_case(si, tiles)
  for _, t in pairs(tiles or {}) do
    for _, va in pairs(storage.verbose_areas or {}) do
      if in_area(va, si, t.position.x + 0.5, t.position.y + 0.5) then return va.case end
    end
  end
end

local function fmt_val(k, v)
  local t = type(v)
  if k == "tiles" and t == "table" then
    local ps = {}
    for _, tp in pairs(v) do ps[#ps + 1] = lg.pos(tp.position) end
    return "[" .. table.concat(ps, ";") .. "]"
  end
  if t == "userdata" or (t == "table" and v.object_name) then
    local ok, on = pcall(function() return v.object_name end)
    if ok and on == "LuaEntity" then return lg.ent(v) end
    local ok2, nm = pcall(function() return v.name end)
    return tostring(ok and on or "userdata") .. ((ok2 and type(nm) == "string") and (":" .. nm) or "")
  end
  if t == "table" then
    local s = lg.ser(v)
    if #s > 300 then s = s:sub(1, 300) .. "..." end
    return s
  end
  return tostring(v)
end

local function generic(e, name, case)
  local keys = {}
  for k in pairs(e) do
    if k ~= "name" and k ~= "tick" then keys[#keys + 1] = k end
  end
  table.sort(keys)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. fmt_val(k, e[k]) end
  lg.out("EV " .. name .. " case=" .. tostring(case) .. " " .. table.concat(parts, " "))
end

local function built(e, path)
  local ent = e.entity
  local tags = e.tags
  local e1 = storage.E1
  if e1 and ent.valid and ent.position.x == e1.pos.x and ent.position.y == e1.pos.y
      and track.hooks.E1_rebuilt then
    track.hooks.E1_rebuilt(ent, tags, path)
  end
  local id = tags and tags.seb_instance
  local inst = id and storage.inst[id]
  if inst then
    track.on_entity_built(inst, ent, path, tags)
    return
  end
  storage.untagged = storage.untagged or {}
  storage.untagged[path] = (storage.untagged[path] or 0) + 1
  local case = verbose_case(ent)
  if case or storage.window then
    lg.out("BUILT_UNTAGGED path=" .. path .. " case=" .. tostring(case or storage.window)
      .. " ent=" .. lg.ent(ent) .. " tags=" .. lg.ser(tags))
  end
end

local function tiles(e, path, what)
  local touched = track.on_tiles(e.surface_index, e.tiles, path, what)
  if next(touched) == nil then
    local case = storage.window or tiles_case(e.surface_index, e.tiles)
    if case then generic(e, "UNOWNED_TILES_" .. what .. "_" .. path, case) end
  end
end

local H = {}
H.on_robot_built_entity = function(e) built(e, "robot") end
H.script_raised_revive = function(e) built(e, "script_revive") end
H.on_built_entity = function(e) built(e, "player") end
H.on_space_platform_built_entity = function(e) built(e, "platform") end
H.on_robot_built_tile = function(e) tiles(e, "robot", "built") end
H.on_space_platform_built_tile = function(e) tiles(e, "platform", "built") end
H.on_player_built_tile = function(e) tiles(e, "player", "built") end
H.on_robot_mined_tile = function(e) tiles(e, "robot", "mined") end
H.on_space_platform_mined_tile = function(e) tiles(e, "platform", "mined") end
H.on_player_mined_tile = function(e) tiles(e, "player", "mined") end

H.script_raised_built = function(e)
  local ent = e.entity
  storage.raised_built = storage.raised_built or {}
  local k = ent and ent.valid and ent.name or "invalid"
  storage.raised_built[k] = (storage.raised_built[k] or 0) + 1
  local case = verbose_case(ent) or storage.window
  if case then
    lg.out("EV_DETAIL script_raised_built case=" .. case .. " ent=" .. lg.ent(ent)
      .. " tags_at_raise=" .. lg.ser(ent and ent.valid and ent.type == "entity-ghost" and ent.tags or nil))
  end
end

H.on_object_destroyed = function(e)
  local r = storage.regs[e.registration_number]
  if not r then
    lg.out("DESTROYED unknown reg=" .. tostring(e.registration_number) .. " useful_id=" .. tostring(e.useful_id)
      .. " type=" .. tostring(e.type))
    return
  end
  storage.regs[e.registration_number] = nil
  track.on_destroyed(storage.inst[r.inst], r, e)
end

local function dispatch(name)
  local h = H[name]
  return function(e)
    local counts = storage.ev_count
    if counts then counts[name] = (counts[name] or 0) + 1 end
    if h then h(e) end
    if storage.window then
      generic(e, name, storage.window)
    elseif not h then
      local case = verbose_case(entity_of(e))
      if case then generic(e, name, case) end
    end
  end
end

function E.register()
  for name, id in pairs(defines.events) do
    if not SKIP[name] then
      local ok, err = pcall(script.on_event, id, dispatch(name))
      if not ok then log("SEB_SPIKE could not register " .. name .. ": " .. tostring(err)) end
    end
  end
end

return E
