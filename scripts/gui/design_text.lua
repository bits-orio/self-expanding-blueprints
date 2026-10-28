-- Words for a design: its one-line description in the list and its tooltip
-- (size, what it is made of, how it grows), so designs can be told apart
-- without opening them.

local const = require("scripts.const")
local pools = require("scripts.core.pools")
local limits = require("scripts.core.limits")
local library = require("scripts.core.library")
local books = require("scripts.core.books")

local design_text = {}

local TOP_PARTS = 6
local TOP_TILES = 2

-- Counts of `key` over a list, most common first (ties by name, so every
-- peer and every redraw agrees).
local function tally(list, exists)
  local counts, order = {}, {}
  for _, e in ipairs(list or {}) do
    local name = e.name
    if exists(name) then
      if not counts[name] then order[#order + 1] = name end
      counts[name] = (counts[name] or 0) + 1
    end
  end
  table.sort(order, function(a, b) return counts[a] > counts[b] or (counts[a] == counts[b] and a < b) end)
  return counts, order
end

local function listed(out, list, exists, kind, top)
  local counts, order = tally(list, exists)
  for i = 1, math.min(#order, top) do
    out[#out + 1] = counts[order[i]] .. " × [" .. kind .. "=" .. order[i] .. "]"
  end
  if #order > top then out[#out + 1] = "…" end
end

local function is_entity(name) return prototypes.entity[name] ~= nil end
local function is_tile(name) return prototypes.tile[name] ~= nil end

-- "8 × [entity=solar-panel]   4 × [entity=accumulator]   …"
function design_text.parts(prepared)
  local out = {}
  listed(out, prepared.placements, is_entity, "entity", TOP_PARTS)
  listed(out, prepared.tiles, is_tile, "tile", TOP_TILES)
  return table.concat(out, "   ")
end

function design_text.size(prepared)
  local b = prepared.bounds
  return b.right - b.left, b.bottom - b.top
end

-- How it grows, in one line.
function design_text.growth(prepared)
  local sockets = #prepared.sockets
  if sockets == 0 then return { "seb-gui.design-plain" } end
  local named = 0
  for _, s in ipairs(prepared.sockets) do
    if s.target.kind == "named" then named = named + 1 end
  end
  local plug = prepared.entry and { "seb-gui.design-with-plug" } or ""
  if named > 0 then return { "seb-gui.design-sockets-named", sockets, named, plug } end
  return { "seb-gui.design-sockets", sockets, plug }
end

-- "In the book Outposts" when sockets can reach it through a pool, or nil.
function design_text.pools(design)
  local names = pools.of(design)
  if #names == 0 then return nil end
  return { "seb-gui.design-pools", table.concat(names, ", ") }
end

-- Refusals that name a fixed ceiling, and the ceiling.
local CEILINGS = {
  [const.REASON.too_many_sockets] = { "seb-error.too-many-sockets", const.MAX_DESIGN_SOCKETS },
  [const.REASON.too_many_poles] = { "seb-error.too-many-poles", const.MAX_DESIGN_POLES },
  [books.TOO_BIG] = { "seb-error.book-too-big", const.MAX_BOOK_CHILDREN },
  [books.TOO_MANY_PARTS] = { "seb-error.book-too-many-parts", const.MAX_BOOK_PARTS },
}

-- Why a blueprint is refused or a design cannot be stamped, with the map
-- limits a refusal names (limits.lua). Without a part limit, a design is
-- only ever too wide.
function design_text.error(reason, force_index)
  local ceiling = CEILINGS[reason]
  if ceiling then return { ceiling[1], ceiling[2] } end
  if reason == const.REASON.too_many_designs then
    return { "seb-error.too-many-designs", limits.max_designs(force_index) }
  end
  if reason == const.REASON.design_too_big then
    local parts = limits.of(force_index, "design_parts")
    if parts == 0 then return { "seb-reason.design-too-big" } end
    return { "seb-error.design-too-big", parts, const.MAX_DESIGN_SPAN }
  end
  return { "seb-error." .. (reason or "unknown") }
end

function design_text.describe(design)
  local prepared = design.prepared
  if not (prepared and prepared.ok) then
    return { "seb-gui.design-error", design_text.error(prepared and prepared.error, design.force_index) }
  end
  return design_text.growth(prepared)
end

function design_text.tooltip(design)
  local prepared = design.prepared
  local head = { "seb-gui.design-heading", design.name, design.id, design.version }
  if not (prepared and prepared.ok) then return { "", head, "\n", design_text.describe(design) } end
  local w, h = design_text.size(prepared)
  return {
    "", head, "\n", { "seb-gui.design-size", w, h }, "\n", design_text.parts(prepared), "\n",
    design_text.growth(prepared), "\n\n", { "seb-gui.select-design" },
  }
end

design_text.SOCKET_ICON = "[img=item/" .. const.SOCKET .. "]"
design_text.PLUG_ICON = "[img=item/" .. const.ENTRY .. "]"

return design_text
