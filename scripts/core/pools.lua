-- Pools: a labelled book's designs, in order, under the book's name
-- (DESIGN.md "Pool"). A socket that names a pool tries its designs in turn
-- and stamps the first that fits, so one book can hold a corner piece, a
-- junction or an outpost for each ore. Kept per force beside the library:
-- storage.libraries[force_index].pools[name] = {design ids}.

local pools = {}

-- resolve(force_index, id): the design with that id, or nil. Set by
-- library.lua (library.get) so a pool hands out designs the way the library
-- does, prepared afresh after a mod change.
pools.resolve = nil

local function pools_of_force(force_index)
  local lib = storage.libraries[force_index]
  return lib and lib.pools
end

-- The ids in order, each once: at one spot a design can only fail the same
-- way again, so a book holding one design many times (blueprints of one
-- name are versions of one design) must not make a socket try it as often.
local function once(ids)
  local seen, list = {}, {}
  for _, id in ipairs(ids) do
    if not seen[id] then
      seen[id] = true
      list[#list + 1] = id
    end
  end
  return list
end

-- Makes `name` the pool of these designs, replacing an older one.
function pools.set(force_index, name, ids)
  local lib = storage.libraries[force_index]
  lib.pools = lib.pools or {}
  lib.pools[name] = once(ids)
end

-- The designs of the pool `name`, in order (deleted ones left out), or nil.
-- Each once, also from a pool kept before pools.set dropped repeats.
function pools.designs(force_index, name)
  local all = pools_of_force(force_index)
  local ids = all and all[name]
  if not ids then return nil end
  local list = {}
  for _, id in ipairs(once(ids)) do list[#list + 1] = pools.resolve(force_index, id) end
  return list
end

-- The names of the pools a design is in, sorted.
function pools.of(design)
  local names = {}
  for name, ids in pairs(pools_of_force(design.force_index) or {}) do
    for _, id in ipairs(ids) do
      if id == design.id then
        names[#names + 1] = name
        break
      end
    end
  end
  table.sort(names)
  return names
end

-- A deleted design leaves every pool; an emptied pool goes.
function pools.forget(design)
  local all = pools_of_force(design.force_index)
  for name, ids in pairs(all or {}) do
    for i = #ids, 1, -1 do
      if ids[i] == design.id then table.remove(ids, i) end
    end
    if #ids == 0 then all[name] = nil end
  end
end

return pools
