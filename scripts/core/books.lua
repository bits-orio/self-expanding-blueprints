-- What a held blueprint or book holds: one blueprint (a stack, or a record
-- picked from the blueprint library), or every set-up blueprint of a book,
-- books inside books included. A labelled book of blueprints only also
-- becomes a pool: its designs, in order, under the book's name, for sockets
-- that name it. A book holding other books is a shelf, no pool itself: each
-- labelled book in it (at any depth) is one, so the library a team exports
-- (fill_book: a book per pool) comes back with its pools.
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

-- The label a library export gets (fill_book): never a pool name.
books.EXPORT_LABEL = "Self-Expanding Blueprints"

local function has_books(children)
  for _, child in ipairs(children) do
    if not books.is_single_blueprint(child) then return true end
  end
  return false
end

-- The pool a book is, given what it holds: its label, unless it holds
-- books (a shelf) or is a library export.
local function pool_of(book, children)
  local label = book.label
  if not label or label == "" or label == books.EXPORT_LABEL or has_books(children) then return nil end
  return label
end

-- Each set-up blueprint inside a book, books inside books included, into
-- walk.found while walk.seen stays within the ceiling, and each pool's
-- blueprints (their places in walk.found) into walk.pools[name]. False once
-- it would not stay within.
local function collect(book, walk)
  local children, looked = children_of(book, const.MAX_BOOK_CHILDREN - walk.seen)
  if not children then return false end
  walk.seen = walk.seen + looked
  local pool = pool_of(book, children)
  local members = pool and (walk.pools[pool] or {})
  if pool then walk.pools[pool] = members end
  for _, child in ipairs(children) do
    if books.is_single_blueprint(child) then
      if child.is_blueprint_setup() then
        walk.found[#walk.found + 1] = child
        if members then members[#members + 1] = #walk.found end
      end
    elseif not collect(child, walk) then
      return false
    end
  end
  return true
end

-- Every blueprint a source holds: itself, or each set-up blueprint of a book.
-- The second result is true for a book bigger than a walk looks at, whose
-- list is cut short; the third, the pools it holds: {name = {places in the
-- list}}.
function books.blueprints_in(source)
  if books.is_single_blueprint(source) then return { source }, false, {} end
  local walk = { seen = 0, found = {}, pools = {} }
  local whole = collect(source, walk)
  return walk.found, not whole, walk.pools
end

-- Why a book bigger than a walk looks at is refused.
books.TOO_BIG = "book-too-big"
books.TOO_MANY_PARTS = "book-too-many-parts"

-- A labelled book's designs become the pool of that name, replacing an
-- older pool of the same name. Returns the name, or nil for no pool.
function books.pool(force_index, name, ids)
  if not name or #ids == 0 then return nil end
  pools.set(force_index, name, ids)
  return name
end

-- Each pool a book held, from its blueprints' places in the walk and the
-- design ids they registered as (`ids[place]`, nil for one that failed).
-- Returns the pool names made, sorted.
function books.pools_from(force_index, held, ids)
  local names = {}
  for name, places in pairs(held) do
    local list = {}
    for _, place in ipairs(places) do
      if ids[place] then list[#list + 1] = ids[place] end
    end
    if books.pool(force_index, name, list) then names[#names + 1] = name end
  end
  table.sort(names)
  return names
end

-- Registers a held blueprint, or every blueprint of a held book. Returns the
-- list of designs registered or updated, the first failure reason, and the
-- name of the pool a labelled book became. A book bigger than a walk looks
-- at registers nothing.
function books.register_all(force_index, source)
  local blueprints, over, held = books.blueprints_in(source)
  if over then return {}, books.TOO_BIG end
  local designs, ids, first_failure = {}, {}, nil
  for place, blueprint in ipairs(blueprints) do
    local design, reason = library.register_string(force_index, books.export_of(blueprint))
    if design then
      designs[#designs + 1] = design
      ids[place] = design.id
    else
      first_failure = first_failure or reason
    end
  end
  if #designs == 0 and not first_failure then first_failure = "not-a-blueprint" end
  local made = books.pools_from(force_index, held, ids)
  return designs, first_failure, made[1], made
end

-- Puts `source` (a stack, or stack data) into the next slot of a book's
-- inventory (`into` = {inventory, filled}); returns that slot, or nil.
local function put(into, source)
  if into.inventory.insert(source) == 0 then return nil end
  into.filled = into.filled + 1
  local slot = into.inventory[into.filled]
  return slot.valid_for_read and slot or nil
end

-- A design's registered blueprint, labelled with the design's name.
local function put_design(into, design)
  local source = library.stack(design)
  local slot = source.valid_for_read and put(into, source)
  if slot then slot.label = design.name end
end

-- Turns `book` (an empty item stack) into a blueprint book of every design
-- of the force, as registered and labelled with their names: each pool a
-- book of its own, under the pool's name and in its order, and the designs in
-- no pool loose beside them. A library to keep, or to add in another save:
-- adding it registers each blueprint and makes the pools again.
function books.fill_book(force_index, book)
  book.set_stack { name = "blueprint-book" }
  book.label = books.EXPORT_LABEL
  local top = { inventory = book.get_inventory(defines.inventory.item_main), filled = 0 }
  local names, pooled = {}, {}
  for name in pairs(pools.all(force_index)) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    local slot = put(top, { name = "blueprint-book" })
    if slot then
      slot.label = name
      local shelf = { inventory = slot.get_inventory(defines.inventory.item_main), filled = 0 }
      for _, design in ipairs(pools.designs(force_index, name)) do
        put_design(shelf, design)
        pooled[design.id] = true
      end
    end
  end
  for _, design in ipairs(library.list(force_index)) do
    if not pooled[design.id] then put_design(top, design) end
  end
end

return books
