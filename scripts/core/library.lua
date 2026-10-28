-- Per-force design libraries. Each design is a blueprint copied into a slot
-- of the force's script inventory, so it survives the player's own library
-- edits and needs no chest. Registering a blueprint whose name is already
-- taken creates a new version of that design; instances keep the version
-- they were stamped from. What a held book holds, and the pool a labelled
-- book becomes, are books.lua's.
--
-- The map caps a force's designs (D45): a new one past the cap is refused,
-- a new version never is, and no setting lets a library past
-- const.MAX_LIBRARY_DESIGNS. Registering is charged to the force's share of
-- server time (budget.lua). A stale design (stale.lua) is prepared again
-- before get or find hands it out, free of the size limits.

local const = require("scripts.const")
local prepare = require("scripts.core.prepare")
local registry = require("scripts.core.registry")
local gallery = require("scripts.core.gallery")
local pools = require("scripts.core.pools")
local limits = require("scripts.core.limits")
local budget = require("scripts.core.budget")

local library = {}

-- hooks.new_version(design): twins.lua's, once a design took a new version.
library.hooks = {}

local GROW_SLOTS = 10
local MAX_SLOTS = 65535   -- LuaInventory.resize takes a uint16

-- Designs the due-tick queue prepares (a book added from the window, the
-- designs a mod change left stale) stop for the run once about this many
-- parts are done; one bigger design goes alone.
library.RUN_PARTS = 500

-- The parts a design's preparation handles, for that bound.
function library.parts_of(design)
  local prepared = design.prepared or {}
  return prepared.parts or (prepared.entity_count or 0) + (prepared.tile_count or 0)
end

function library.of(force_index)
  local lib = storage.libraries[force_index]
  if not lib then
    lib = { inventory = game.create_inventory(GROW_SLOTS), designs = {}, by_name = {}, next_name = 1 }
    storage.libraries[force_index] = lib
  end
  return lib
end

local function free_slot(lib)
  local _, index = lib.inventory.find_empty_stack()
  if index then return index end
  local size = #lib.inventory
  lib.inventory.resize(math.min(size + GROW_SLOTS, MAX_SLOTS))
  return size + 1
end

-- Whether the inventory has room for a design's two slots (it holds only
-- blueprints, one per slot): with room, free_slot always finds one.
local function has_room(lib)
  return MAX_SLOTS - lib.inventory.get_item_count() >= 2
end

local function first_icon(stack)
  local icons = stack.preview_icons
  return icons and icons[1] and icons[1].signal or nil
end

local function default_name(lib)
  return "Design " .. lib.next_name
end

-- Imports into a fresh slot; returns the slot or nil and a reason.
local function store(lib, export_string)
  local slot = free_slot(lib)
  local stack = lib.inventory[slot]
  local ok, result = pcall(stack.import_stack, export_string)
  if not ok or result == 1 or not stack.valid_for_read or not (stack.is_blueprint or stack.is_blueprint_book) then
    stack.clear()
    return nil, "invalid-design"
  end
  if stack.is_blueprint_book then
    stack.clear()
    return nil, "book-not-blueprint"
  end
  if not stack.is_blueprint_setup() then
    stack.clear()
    return nil, "empty-blueprint"
  end
  return slot
end

local function blank_slot(lib)
  local slot = free_slot(lib)
  lib.inventory[slot].set_stack { name = "blueprint" }
  return slot
end

-- Prepares a version being registered, held to the size limits. The force
-- pays for the lab work when it was done: calibration stamps and picture,
-- and the parts.
local function prepared_for(version, source, copy)
  local prepared = prepare.run(version, source, copy, { limits = true })
  if prepared.parts then
    budget.charge(version.force_index, budget.COST.register_design + prepared.parts * budget.COST.register_part
      + (prepared.pole_count or 0) * budget.COST.register_pole)
  end
  return prepared
end

-- Each design holds two slots: the player's blueprint as registered, and
-- the stamping copy prepare.lua derives from it.
local function refresh(design, lib)
  design.stamp_slot = design.stamp_slot or blank_slot(lib)
  local source = lib.inventory[design.slot]
  design.icon = first_icon(source) or design.icon
  design.prepared = prepare.run(design, source, lib.inventory[design.stamp_slot])
  gallery.build(design, lib.inventory[design.stamp_slot])
end

-- A new design is prepared before it is kept. One the size limits refuse is
-- not kept; one that fails otherwise is kept, unstampable, with its reason.
-- A hidden one (a mirror twin, twins.lua) has no name to find it by, no
-- picture, and does not count toward the force's designs.
local function add(lib, force_index, slot, name, hidden)
  local design = { force_index = force_index, name = name, version = 1, slot = slot, hidden = hidden }
  design.stamp_slot = blank_slot(lib)
  local source, copy = lib.inventory[slot], lib.inventory[design.stamp_slot]
  design.prepared = prepared_for(design, source, copy)
  if prepare.LIMITS[design.prepared.error] then
    source.clear()
    copy.clear()
    return nil, design.prepared.error
  end
  design.id = registry.new_design_id()
  design.icon = first_icon(source)
  lib.designs[design.id] = design
  if hidden then
    lib.hidden_count = (lib.hidden_count or 0) + 1
    return design, true
  end
  lib.next_name = lib.next_name + 1
  lib.by_name[name] = design.id
  gallery.build(design, copy)
  return design, true
end

-- A new version is prepared beside the working one and replaces it only if
-- it can be stamped: a failed update leaves the design as it was.
local function replace(lib, design, slot)
  local next_version = { force_index = design.force_index, version = design.version + 1 }
  local copy = blank_slot(lib)
  local prepared = prepared_for(next_version, lib.inventory[slot], lib.inventory[copy])
  if not prepared.ok then
    lib.inventory[slot].clear()
    lib.inventory[copy].clear()
    return nil, prepared.error
  end
  lib.inventory[design.slot].clear()
  lib.inventory[design.stamp_slot].clear()
  design.slot, design.stamp_slot, design.version, design.prepared = slot, copy, next_version.version, prepared
  design.icon = first_icon(lib.inventory[slot]) or design.icon
  design.stale = nil
  if design.hidden then return design, false end
  gallery.build(design, lib.inventory[copy])
  if library.hooks.new_version then library.hooks.new_version(design) end
  return design, false
end

-- Whether the force has as many designs as it may keep: a new one would be
-- refused (a new version never is).
function library.full(force_index)
  local lib = storage.libraries[force_index]
  return lib ~= nil and table_size(lib.designs) - (lib.hidden_count or 0) >= limits.max_designs(force_index)
end

-- Whether a held blueprint (a stack or a library record) has more parts,
-- tiles included, than a design may: asked before it is exported, which
-- costs about 12 µs per part in one tick whatever then refuses it.
library.oversized = prepare.oversized

-- Registers one blueprint (as an export string) under `name`, or under its
-- label. Returns the design and whether it is new, or nil and a reason.
-- Making and reading the string is charged by its length, refused or not.
function library.register_string(force_index, export_string, name)
  budget.charge(force_index, #export_string * budget.COST.blueprint_byte)
  local lib = library.of(force_index)
  if not has_room(lib) then return nil, const.REASON.too_many_designs end
  local slot, reason = store(lib, export_string)
  if not slot then return nil, reason end
  local stack = lib.inventory[slot]
  name = (name and name ~= "") and name or (stack.label ~= "" and stack.label) or default_name(lib)
  local existing = lib.designs[lib.by_name[name]]
  if existing then return replace(lib, existing, slot) end
  if library.full(force_index) then
    stack.clear()
    return nil, const.REASON.too_many_designs
  end
  return add(lib, force_index, slot, name)
end

-- Registers what `write(stack)` puts in a fresh slot as a new hidden design
-- (a mirror twin, twins.lua) or `existing`'s next version; nil and a reason.
function library.register_hidden(force_index, name, write, existing)
  local lib = library.of(force_index)
  if not has_room(lib) then return nil, const.REASON.too_many_designs end
  local slot = free_slot(lib)
  local ok, why = write(lib.inventory[slot])
  if not ok then
    lib.inventory[slot].clear()
    return nil, why
  end
  if existing then return replace(lib, existing, slot) end
  return add(lib, force_index, slot, name, true)
end

-- Prepares the design's current version again: prototypes may have changed
-- under it (stale.lua). Its parts are not charged: a mod change is
-- nobody's request.
function library.reprepare(design)
  design.stale = nil
  refresh(design, storage.libraries[design.force_index])
end

-- Nothing stamps from a preparation made before a mod change.
local function fresh(design)
  if design and design.stale then library.reprepare(design) end
  return design
end

function library.get(force_index, design_id)
  local lib = storage.libraries[force_index]
  return lib and fresh(lib.designs[design_id])
end

-- By name; or, unless `exact`, by a name it had before a rename (naming.lua),
-- as sockets drawn with the old name still mean it.
function library.find(force_index, name, exact)
  local lib = storage.libraries[force_index]
  if not lib then return nil end
  return fresh(lib.designs[lib.by_name[name] or (not exact and (lib.aliases or {})[name]) or 0])
end

-- A pool's designs come through get as well.
pools.resolve = library.get

-- The player's blueprint as registered.
function library.stack(design)
  return storage.libraries[design.force_index].inventory[design.slot]
end

-- The copy that gets stamped (see prepare.lua).
function library.stamp_stack(design)
  return storage.libraries[design.force_index].inventory[design.stamp_slot]
end

-- Designs of a force in id order, as they are (a stale one too: listing is
-- not use).
function library.list(force_index)
  local lib = storage.libraries[force_index]
  local list = {}
  for _, design in pairs(lib and lib.designs or {}) do
    if not design.hidden then list[#list + 1] = design end
  end
  table.sort(list, function(a, b) return a.id < b.id end)
  return list
end

-- A design goes with its mirror twin.
function library.delete(design)
  local lib = storage.libraries[design.force_index]
  local twin = design.twin_id and lib.designs[design.twin_id]
  if twin then library.delete(twin) end
  lib.inventory[design.slot].clear()
  if design.stamp_slot then lib.inventory[design.stamp_slot].clear() end
  if design.hidden then
    lib.hidden_count = lib.hidden_count - 1
  else
    lib.by_name[design.name] = nil
  end
  for name, id in pairs(lib.aliases or {}) do
    if id == design.id then lib.aliases[name] = nil end
  end
  lib.designs[design.id] = nil
  gallery.remove(design.id)
  pools.forget(design)
end

function library.drop_force(force_index)
  local lib = storage.libraries[force_index]
  if not lib then return end
  for id in pairs(lib.designs) do gallery.remove(id) end
  if lib.inventory.valid then lib.inventory.destroy() end
  storage.libraries[force_index] = nil
end

return library
