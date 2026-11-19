-- Library entries. A design registered from a record of the blueprint
-- library (the player's own shelf, or the game's) remembers that entry, so
-- the same entry held again is that design's next version whatever its
-- label says by then, and an entry edited in the library tells the player
-- that its design still holds the older blueprint (D62).
--
-- An entry is known by its shelf and its id on that shelf (Factorio 2.1.25:
-- LuaRecord.shelf_index and record_id). Measured: the id stays through a
-- move to another slot or into a book, a label or content edit and a save
-- and load; an entry taken out and put back, a copy and a re-import get a
-- new one. A player's shelf belongs to the user, not the save, so the id
-- alone is never trusted: the label last seen on the entry must still be
-- its label, and a fingerprint of its blueprint string says whether it
-- changed. Older engines have neither field and carry no record on the GUI
-- events: every read here is guarded, and nothing is remembered there, so
-- blueprints are told apart by label alone as before.

local library = require("scripts.core.library")
local books = require("scripts.core.books")
local prepare = require("scripts.core.prepare")
local budget = require("scripts.core.budget")

local records = {}

-- A blueprint string is a zlib stream, which ends in a checksum of all it
-- holds: its length and its last characters change with any edit, and cost
-- nothing to read.
local TAIL = 24

-- A field of a record, or nil where the engine has none (it throws there).
local function read(source, field)
  local ok, value = pcall(function() return source[field] end)
  if ok then return value end
end

-- The entry a held or opened blueprint is; nil for an item stack, a book's
-- preview the engine tells nothing of, and every record on older engines.
function records.key(source)
  if not source or read(source, "object_name") ~= "LuaRecord" then return nil end
  local shelf, id = read(source, "shelf_index"), read(source, "record_id")
  if type(shelf) ~= "number" or type(id) ~= "number" then return nil end
  return shelf .. ":" .. id
end

function records.fingerprint(export_string)
  return #export_string .. ":" .. export_string:sub(-TAIL)
end

-- The force's design that came from the entry, while it still holds the
-- version it took from it: a version registered from anything else lets the
-- entry go.
local function linked(force_index, key)
  local lib = storage.libraries[force_index]
  local id = lib and lib.records and lib.records[key]
  if not id then return nil end
  local design = lib.designs[id]
  local link = design and design.record
  if link and link.key == key and link.version == design.version then return design end
  lib.records[key] = nil
  if link and link.key == key then design.record = nil end
end

-- The design a held library entry is the next version of: the one that
-- came from it, when the entry still carries the label last seen on it and
-- that label names no other design (a name always wins, as before).
function records.design_for(force_index, source)
  local key = records.key(source)
  local design = key and linked(force_index, key)
  if not design then return nil end
  local label = read(source, "label") or ""
  if label ~= design.record.label then return nil end
  local named = library.find(force_index, label, true)
  if named and named ~= design then return nil end
  return design
end

-- After `design` took a version from `source`: it belongs to that library
-- entry now, or to none when the source is no entry.
function records.link(design, source, export_string)
  local lib = library.of(design.force_index)
  lib.records = lib.records or {}
  local old = design.record
  if old and lib.records[old.key] == design.id then lib.records[old.key] = nil end
  design.record = nil
  local key = records.key(source)
  if not key then return end
  local other = lib.designs[lib.records[key] or 0]
  if other then other.record = nil end
  design.record = {
    key = key, label = read(source, "label") or "", version = design.version,
    print = records.fingerprint(export_string),
  }
  lib.records[key] = design.id
end

-- Registers one blueprint a player holds (a stack or a library entry) under
-- `name`, or as the next version of the design its entry belongs to, or
-- under its label. Returns as library.register_string does.
function records.register(force_index, source, name)
  local known = not name and records.design_for(force_index, source)
  local text = books.export_of(source)
  local design, created = library.register_string(force_index, text, name or (known and known.name) or nil)
  if design then records.link(design, source, text) end
  return design, created
end

-- The fingerprint of an entry as it is now; nil while the engine holds only
-- its preview (another player's shelf, until they close it) or it is too big
-- to be a design, so too big to export for a look.
local function print_of(force_index, record)
  if read(record, "is_preview") or prepare.oversized(force_index, record) then return nil end
  local ok, text = pcall(record.export_record)
  if not (ok and type(text) == "string") then return nil end
  budget.charge(force_index, #text * budget.COST.blueprint_byte)
  return records.fingerprint(text)
end

-- A library entry was closed, perhaps edited: the design that came from it
-- follows its label, and is returned the first time the entry is seen to
-- differ from what the design holds.
function records.follow(force_index, record)
  local key = records.key(record)
  local design = key and linked(force_index, key)
  if not design then return nil end
  local link = design.record
  link.label = read(record, "label") or ""
  local print = print_of(force_index, record)
  if not print or print == link.print or print == link.seen then return nil end
  link.seen = print
  return design
end

-- The blueprint or book record a GUI event carries; nil on engines whose
-- events carry none.
local function record_of(event)
  local record = read(event, "record")
  if not (record and read(record, "valid")) then return nil end
  local kind = read(record, "type")
  if kind == "blueprint" or kind == "blueprint-book" then return record end
end

-- on_gui_closed. A record opened from the library is read here and not as
-- it opens: by now a player's own entry has reached the server whole
-- (measured in multiplayer: only a preview when it opens), and a Save has
-- been applied.
function records.on_closed(event)
  local record = record_of(event)
  local player = record and game.get_player(event.player_index)
  if not player then return end
  local design = records.follow(player.force.index, record)
  if not design then return end
  player.print({ "seb-message.record-changed", design.record.label, design.name, design.version })
end

return records
