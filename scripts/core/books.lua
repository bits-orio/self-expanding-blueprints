-- What a held blueprint or book holds: one blueprint (a stack, or a record
-- picked from the blueprint library), or every set-up blueprint of a book,
-- books inside books included. A labelled book also becomes a pool: its
-- designs, in order, under the book's name, for sockets that name it.
-- register_all adds a whole book at once, for the remote interface's trusted
-- callers; the window adds a book a few designs at a time (gui/book_queue.lua).
--
-- A walk through a book looks at no more than const.MAX_BOOK_CHILDREN
-- children, counting empty blueprints, planners and the books inside with
-- their own children: an imported string of under a megabyte can hold a
-- quarter of a million, each costs to look at, and a copy of them must fit
-- a script inventory. A bigger book is refused, not walked.

local const = require("scripts.const")
local library = require("scripts.core.library")
local pools = require("scripts.core.pools")

local books = {}

-- The export string of a cursor stack, inventory stack or library record.
function books.export_of(source)
  if source.object_name == "LuaRecord" then return source.export_record() end
  return source.export_stack()
end

-- True for one blueprint (not a book), held as a stack or a library record.
-- Records have no is_blueprint, so they are told apart by type.
function books.is_single_blueprint(source)
  if source.object_name == "LuaRecord" then return source.type == "blueprint" end
  return source.is_blueprint
end

-- What a book holds, as library records or inventory stacks, and how many
-- places it looked at (a record book's highest index, a stack book's
-- slots); nothing for anything else (planners hold no blueprints). Nil when
-- that is more than `room`: then nothing is read.
local function children_of(book, room)
  local list = {}
  if book.object_name == "LuaRecord" then
    if book.type ~= "blueprint-book" then return list, 0 end
    if book.contents_size > room then return nil end
    for _, record in pairs(book.contents) do list[#list + 1] = record end
    return list, book.contents_size
  end
  local inner = book.is_blueprint_book and book.get_inventory(defines.inventory.item_main)
  if not inner then return list, 0 end
  if #inner > room then return nil end
  for i = 1, #inner do
    if inner[i].valid_for_read then list[#list + 1] = inner[i] end
  end
  return list, #inner
end

-- Each set-up blueprint inside a book, books inside books included, into
-- walk.found while walk.seen stays within the ceiling. False once it would
-- not.
local function collect(book, walk)
  local children, looked = children_of(book, const.MAX_BOOK_CHILDREN - walk.seen)
  if not children then return false end
  walk.seen = walk.seen + looked
  for _, child in ipairs(children) do
    if books.is_single_blueprint(child) then
      if child.is_blueprint_setup() then walk.found[#walk.found + 1] = child end
    elseif not collect(child, walk) then
      return false
    end
  end
  return true
end

-- Every blueprint a source holds: itself, or each set-up blueprint of a book.
-- The second result is true for a book bigger than a walk looks at, whose
-- list is cut short.
function books.blueprints_in(source)
  if books.is_single_blueprint(source) then return { source }, false end
  local walk = { seen = 0, found = {} }
  local whole = collect(source, walk)
  return walk.found, not whole
end

-- Why a book bigger than a walk looks at is refused.
books.TOO_BIG = "book-too-big"
books.TOO_MANY_PARTS = "book-too-many-parts"

-- The pool name a book's label gives, or nil (a blueprint, or no label).
function books.pool_name(source)
  local label = source.label
  if books.is_single_blueprint(source) or not label or label == "" then return nil end
  return label
end

-- A labelled book's designs become the pool of that name, replacing an
-- older pool of the same name. Returns the name, or nil for no pool.
function books.pool(force_index, name, ids)
  if not name or #ids == 0 then return nil end
  pools.set(force_index, name, ids)
  return name
end

-- Registers a held blueprint, or every blueprint of a held book. Returns the
-- list of designs registered or updated, the first failure reason, and the
-- name of the pool a labelled book became. A book bigger than a walk looks
-- at registers nothing.
function books.register_all(force_index, source)
  local blueprints, over = books.blueprints_in(source)
  if over then return {}, books.TOO_BIG end
  local designs, ids, first_failure = {}, {}, nil
  for _, blueprint in ipairs(blueprints) do
    local design, reason = library.register_string(force_index, books.export_of(blueprint))
    if design then
      designs[#designs + 1] = design
      ids[#ids + 1] = design.id
    else
      first_failure = first_failure or reason
    end
  end
  if #designs == 0 and not first_failure then first_failure = "not-a-blueprint" end
  return designs, first_failure, books.pool(force_index, books.pool_name(source), ids)
end

-- Turns `book` (an empty item stack) into a blueprint book of every design
-- of the force, as registered and labelled with their names: a library to
-- keep, or to add in another save (adding a book registers each blueprint).
function books.fill_book(force_index, book)
  book.set_stack { name = "blueprint-book" }
  book.label = "Self-Expanding Blueprints"
  local inner = book.get_inventory(defines.inventory.item_main)
  local slot = 0
  for _, design in ipairs(library.list(force_index)) do
    local source = library.stack(design)
    if source.valid_for_read and inner.insert(source) > 0 then
      slot = slot + 1
      if inner[slot].valid_for_read then inner[slot].label = design.name end
    end
  end
end

return books
