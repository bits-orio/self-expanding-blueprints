-- The remote interface's design functions (docs/remote-interface.md):
-- registering blueprints and books, listing designs and pools, exporting
-- the library, deleting a design, and naming a design's upgrade research.

local library = require("scripts.core.library")
local books = require("scripts.core.books")
local research = require("scripts.core.research")
local args = require("scripts.remote.args")
local lookup = require("scripts.remote.lookup")

local function design_row(design)
  local prepared = design.prepared or {}
  return {
    id = design.id, name = design.name, version = design.version, icon = design.icon,
    ok = prepared.ok == true, error = prepared.error,
    sockets = prepared.sockets and #prepared.sockets or 0, has_entry = prepared.entry ~= nil,
  }
end

local function ids_of(designs)
  local ids = {}
  for i, design in ipairs(designs) do ids[i] = design.id end
  return ids
end

-- A book string registers every blueprint in it (a labelled book also
-- becomes a pool) and returns the list of their ids instead of one id.
local function register_book(force_index, blueprint_string)
  local inventory = game.create_inventory(1)
  local stack = inventory[1]
  local ok = pcall(stack.import_stack, blueprint_string)
  if not (ok and stack.valid_for_read and stack.is_blueprint_book) then
    inventory.destroy()
    return nil
  end
  local designs, reason, pool = books.register_all(force_index, stack)
  inventory.destroy()
  if #designs == 0 then return false, reason end
  return ids_of(designs), pool
end

-- A blueprint or book itself rather than its string: a library record (one
-- of game.blueprints, say) or an item stack. Registered as it is now; a
-- later edit of the record is a new version only when registered again.
local function register_object(force_index, source, name)
  if source.object_name == "LuaItemStack" and not source.valid_for_read then return nil, "invalid-design" end
  if books.is_single_blueprint(source) then
    local design, created_or_reason = library.register_string(force_index, books.export_of(source), name)
    if not design then return nil, created_or_reason end
    return design.id, created_or_reason
  end
  local designs, reason, pool = books.register_all(force_index, source)
  if #designs == 0 then return nil, reason end
  return ids_of(designs), pool
end

return function(interface)
  function interface.register_design(force, blueprint_string, name)
    local f = lookup.force(force)
    if not f then return nil, "unknown-force" end
    if not args.name(name) then return nil, "invalid-name" end
    local kind = lookup.object_name(blueprint_string)
    if kind == "LuaRecord" or kind == "LuaItemStack" then return register_object(f.index, blueprint_string, name) end
    if type(blueprint_string) ~= "string" then return nil, "invalid-design" end
    local ids, pool = register_book(f.index, blueprint_string)
    if ids then return ids, pool end
    if ids == false then return nil, pool end
    local design, created_or_reason = library.register_string(f.index, blueprint_string, name)
    if not design then return nil, created_or_reason end
    return design.id, created_or_reason
  end

  -- Every design of a force as one blueprint book string (register_design
  -- adds such a book back, in this save or another).
  function interface.export_library(force)
    local f = lookup.force(force)
    if not f then return nil, "unknown-force" end
    local inventory = game.create_inventory(1)
    books.fill_book(f.index, inventory[1])
    local text = inventory[1].export_stack()
    inventory.destroy()
    return text
  end

  function interface.list_pools(force)
    local f = lookup.force(force)
    local lib = f and storage.libraries[f.index]
    local out = {}
    for pool_name, ids in pairs(lib and lib.pools or {}) do
      local copy = {}
      for i, id in ipairs(ids) do copy[i] = id end
      out[pool_name] = copy
    end
    return out
  end

  function interface.list_designs(force)
    local f = lookup.force(force)
    if not f then return {} end
    local rows = {}
    for i, design in ipairs(library.list(f.index)) do rows[i] = design_row(design) end
    return rows
  end

  -- Deletes a design (and its mirror twin): its projects end and its copies
  -- are forgotten, their buildings left standing (lifecycle.lua).
  function interface.delete_design(force, design)
    local f = lookup.force(force)
    if not f then return false, "unknown-force" end
    local d = lookup.design(f.index, design)
    if not d or d.hidden then return false, "unknown-design" end
    library.delete(d)
    return true
  end

  -- Names the technology whose research moves a design's copies to its newest
  -- version (nil clears it).
  function interface.set_upgrade_research(force, design, technology)
    local f = lookup.force(force)
    if not f then return false, "unknown-force" end
    local d = lookup.design(f.index, design)
    if not d then return false, "unknown-design" end
    if technology ~= nil and not prototypes.technology[technology] then return false, "unknown-technology" end
    research.set(d, technology)
    return true
  end
end
