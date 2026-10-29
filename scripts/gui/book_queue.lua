-- A book added from the window registers over several runs of the due-tick
-- queue, a few blueprints per run and only while the team's share of server
-- time lasts (budget.lua), so one click on a big book does not register it
-- all in one tick. The click itself still walks and copies the book in one
-- tick, and one design at the part cap is still one tick. Its blueprints
-- are copied when the button is pressed, so moving or editing the book
-- afterwards changes nothing, except for a library book's blueprints past
-- the first few: exporting a record takes 14 µs a part, so those are read
-- from the library as their turn comes. Each design prints its line as it
-- comes; a labelled book becomes a pool after the last one. A team adds one
-- book at a time, the walk on the click waits for the team's share like any
-- other work, and a book bigger than a walk looks at (books.lua) or than
-- const.MAX_BOOK_PARTS is refused before anything is copied.

local const = require("scripts.const")
local scheduler = require("scripts.core.scheduler")
local budget = require("scripts.core.budget")
local library = require("scripts.core.library")
local prepare = require("scripts.core.prepare")
local books = require("scripts.core.books")
local pools = require("scripts.core.pools")
local registry = require("scripts.core.registry")
local cursor = require("scripts.cursor")
local window = require("scripts.gui.window")
local design_text = require("scripts.gui.design_text")

local book_queue = {}

local KIND = "register-book"
local PER_RUN = 4   -- blueprints tried per run at most (and library.RUN_PARTS), while the budget lasts

local function jobs()
  storage.book_jobs = storage.book_jobs or {}
  return storage.book_jobs
end

-- A job outlives its team's library only if the team was released or
-- merged meanwhile (the library's inventory goes with it).
local function orphaned(job)
  return not (job.library and job.library.valid)
end

local function drop(force_index)
  local job = jobs()[force_index]
  jobs()[force_index] = nil
  if job and job.inventory.valid then job.inventory.destroy() end
end

-- The player who added the book, while they are on and still on its team.
local function owner(job, force_index)
  local player = game.get_player(job.player_index)
  if player and player.connected and player.force.index == force_index then return player end
end

-- Every blueprint of the book in a slot of its own: a stack is copied, and
-- a library record exported (charged by its string's length, as
-- registering one is) while the click's const.BOOK_CLICK_PARTS last. A
-- record past them is kept as it is (records[i]) and read when its turn
-- comes. The list is never longer than a walk looks at.
local function copy_of(list, force_index)
  local inventory, records, room = game.create_inventory(#list), {}, const.BOOK_CLICK_PARTS
  for i, entry in ipairs(list) do
    local blueprint = entry.blueprint
    if blueprint.object_name ~= "LuaRecord" then
      inventory[i].set_stack(blueprint)
    elseif entry.parts <= room then
      room = room - entry.parts
      local text = blueprint.export_record()
      budget.charge(force_index, #text * budget.COST.blueprint_byte)
      inventory[i].import_stack(text)
    else
      records[i] = blueprint
    end
  end
  return inventory, records
end

-- The export string of the job's next blueprint: its copy, or the library
-- record kept for its turn while the library still lets it be read (one
-- deleted meanwhile, or of a player who left, is counted unread).
local function next_string(job)
  local i = job.next
  job.next = i + 1
  local stack = job.inventory[i]
  if stack.valid_for_read then
    local text = stack.export_stack()
    stack.clear()
    return text
  end
  local record = job.records and job.records[i]
  if not record then return nil end
  job.records[i] = nil
  if record.valid and not record.is_preview then return record.export_record() end
  job.unread = (job.unread or 0) + 1
end

-- Registers the next blueprint; returns the parts its preparation handled.
local function register_next(job, force_index)
  local i = job.next
  local text = next_string(job)
  if not text then return 0 end
  local design, reason = library.register_string(force_index, text)
  if not design then
    job.failure = job.failure or reason
    return 0
  end
  job.ids[#job.ids + 1] = design.id
  local place = job.places and job.places[i]
  if place then job.by_place[place] = design.id end
  local player = owner(job, force_index)
  if player then
    player.print({ "seb-message.registered", design.name, design.version })
    if #job.ids == 1 then registry.player(player.index).selected_design = design.id end
  end
  return library.parts_of(design)
end

local function finish(job, force_index)
  drop(force_index)
  local made = books.pools_from(force_index, job.held or {}, job.by_place or {})
  local player = owner(job, force_index)
  if player and #job.ids == 0 then
    cursor.say(player, design_text.error(job.failure or "not-a-blueprint", force_index))
  end
  -- A pool lists each design once, however often the book holds it.
  for _, pool in ipairs(player and made or {}) do
    player.print({ "seb-message.pooled", pool, #pools.designs(force_index, pool) })
  end
  if player and job.unread then player.print({ "seb-message.book-unread", job.unread }) end
  window.refresh_designs(force_index, job.ids[1])
end

local function run(item, now)
  local force_index = item.force_index
  local job = jobs()[force_index]
  if not (job and job.id == item.id) then return end
  if orphaned(job) then return drop(force_index) end
  local tried, parts, registered = 0, 0, #job.ids
  while job.next <= job.count and tried < PER_RUN and parts < library.RUN_PARTS and budget.ready(force_index) do
    parts = parts + register_next(job, force_index)
    tried = tried + 1
  end
  if job.next > job.count then return finish(job, force_index) end
  -- A redraw walks the book each window's player holds: only for news.
  if #job.ids > registered then window.refresh_designs(force_index, job.ids[1]) end
  scheduler.at(now + budget.wait(force_index), item)
end
scheduler.register(KIND, run)

-- The blueprints of a book a design may be made of, each with its parts,
-- and the refusal for any left out: one with more parts (tiles included)
-- than a design may have is never copied or exported (library.oversized).
-- Nil once those that fit pass const.MAX_BOOK_PARTS in all.
local function fitting(force_index, blueprints)
  local list, refused, room = {}, nil, const.MAX_BOOK_PARTS
  for place, blueprint in ipairs(blueprints) do
    local parts = prepare.parts_within(blueprint, room)
    if parts and not prepare.too_many_parts(parts, force_index) then
      room = room - parts
      list[#list + 1] = { blueprint = blueprint, parts = parts, place = place }
    elseif library.oversized(force_index, blueprint) then
      refused = const.REASON.design_too_big
    else
      return nil
    end
  end
  return list, refused
end

-- What the click may add: the book's blueprints that fit and the refusal
-- for any left out, or nil and why none can be.
local function addable(force_index, source)
  local blueprints, over, held = books.blueprints_in(source)
  if over then return nil, books.TOO_BIG end
  local list, refused = fitting(force_index, blueprints)
  if not list then return nil, books.TOO_MANY_PARTS end
  if #list == 0 then return nil, refused or "not-a-blueprint" end
  return list, refused, held
end

-- Starts adding the book `source` (a stack or a library record) for the
-- player's team.
function book_queue.start(player, source)
  local force_index = player.force.index
  local running = jobs()[force_index]
  -- The walk is charged whatever it finds, so a book refused again and
  -- again waits for the team's share like any other work.
  if (running and not orphaned(running)) or not budget.ready(force_index) then
    return cursor.say(player, { "seb-reason.busy" })
  end
  drop(force_index)
  budget.charge(force_index, budget.COST.book_walk)
  local list, refused, held = addable(force_index, source)
  if not list then return cursor.say(player, design_text.error(refused, force_index)) end
  storage.next_book_job = (storage.next_book_job or 0) + 1
  local inventory, records = copy_of(list, force_index)
  jobs()[force_index] = {
    id = storage.next_book_job, player_index = player.index, inventory = inventory, records = records,
    count = #list, next = 1, ids = {}, library = library.of(force_index).inventory, failure = refused,
    -- The book's pools, by the places of their blueprints in it; each
    -- design id registered goes to its place (by_place).
    held = held, places = {}, by_place = {},
  }
  for i, entry in ipairs(list) do jobs()[force_index].places[i] = entry.place end
  scheduler.at(game.tick + 1, { kind = KIND, force_index = force_index, id = storage.next_book_job })
end

return book_queue
