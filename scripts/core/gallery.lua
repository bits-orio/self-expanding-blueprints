-- The gallery: a hidden lab surface holding one copy of every design, so the
-- window can show a picture of it through a camera. A copy is the design's
-- stamping copy built with build_blueprint as ghosts of the design's own
-- force (a camera shows a force its own ghosts, so only that team sees its
-- designs). Ghosts never run, draw no warnings (real entities there show "no
-- power" icons), and no robots ever reach the surface, so nothing builds
-- them. Each design has its own stretch of the surface's x axis (a cell),
-- cleared before every build. A deleted design's cell, or one a design
-- outgrew, is given back and reused before the strip grows, so the strip
-- stays as long as the live designs need; no two cells share a column, so
-- pictures never overlap.

local const = require("scripts.const")
local geometry = require("scripts.core.geometry")
local placement = require("scripts.core.placement")
local labs = require("scripts.core.labs")

local gallery = {}

local MARGIN = 8   -- tiles of empty floor around each copy

-- The free stretches of the strip before next_x, in order of x. A save from
-- before they were kept gets them from the gaps between its cells, and its
-- strip ends at its last cell.
local function free_of(store)
  if store.free then return store.free end
  local taken = {}
  for _, cell in pairs(store.cells) do taken[#taken + 1] = cell end
  table.sort(taken, function(a, b) return a.left < b.left end)
  local free, x = {}, 0
  for _, cell in ipairs(taken) do
    if cell.left > x then free[#free + 1] = { left = x, width = cell.left - x } end
    x = math.max(x, cell.left + cell.width)
  end
  store.free, store.next_x = free, x
  return free
end

-- The left edge of a stretch `width` wide: the first free one that fits,
-- else a new one at the end of the strip.
local function take(store, width)
  local free = free_of(store)
  for i, stretch in ipairs(free) do
    if stretch.width >= width then
      local left = stretch.left
      stretch.left, stretch.width = left + width, stretch.width - width
      if stretch.width == 0 then table.remove(free, i) end
      return left
    end
  end
  local left = store.next_x
  store.next_x = left + width
  return left
end

-- Gives a cell's stretch back, joined to free neighbours; a stretch that
-- ends the strip shortens it instead.
local function give_back(store, cell)
  local free = free_of(store)
  local i = 1
  while free[i] and free[i].left < cell.left do i = i + 1 end
  table.insert(free, i, { left = cell.left, width = cell.width })
  local after = free[i + 1]
  if after and free[i].left + free[i].width == after.left then
    free[i].width = free[i].width + after.width
    table.remove(free, i + 1)
  end
  local before = free[i - 1]
  if before and before.left + before.width == free[i].left then
    before.width = before.width + free[i].width
    table.remove(free, i)
    i = i - 1
  end
  if free[i].left + free[i].width == store.next_x then
    store.next_x = free[i].left
    table.remove(free, i)
  end
end

local function area_of(box)
  return { { box.left, box.top }, { box.right, box.bottom } }
end

-- Everything in a cell goes (copies, and whatever map generation left).
local function clear(lab, box)
  for _, entity in pairs(lab.find_entities_filtered { area = area_of(box) }) do
    if entity.valid and entity.type ~= "character" then entity.destroy() end
  end
end

local function cell_box(cell)
  return geometry.box(cell.left, 0, cell.left + cell.width, cell.height)
end

-- Rounded up to whole chunks, so a design that grows a little keeps its cell.
local function chunks(n)
  return math.ceil(n / geometry.CHUNK) * geometry.CHUNK
end

-- A cell `w` x `h` tiles wide plus margins: the design's old one if it is
-- big enough, else the first stretch that fits (the old one is emptied and
-- given back first, so a design can grow into it).
local function cell_for(lab, store, design_id, w, h)
  local cell = store.cells[design_id]
  if cell and cell.width >= w + 2 * MARGIN and cell.height >= h + 2 * MARGIN then return cell end
  if cell then
    clear(lab, cell_box(cell))
    give_back(store, cell)
  end
  local width = chunks(w + 2 * MARGIN)
  cell = { left = take(store, width), width = width, height = chunks(h + 2 * MARGIN) }
  store.cells[design_id] = cell
  return cell
end

-- A part whose placement check fails on the lab (a drill with no ore under
-- it, a pump with no water) gets its ghost made directly, so it still shows.
local function fill_missing(lab, design, prepared, position, built)
  local present = {}
  for _, ghost in pairs(built) do
    if ghost.valid and ghost.type == "entity-ghost" then
      present[ghost.ghost_name .. "@" .. geometry.position_key(ghost.position)] = true
    end
  end
  for _, e in ipairs(prepared.placements) do
    local p = placement.world(prepared, e.position, position, geometry.NORTH)
    if not present[e.name .. "@" .. geometry.position_key(p)] and prototypes.entity[e.name] then
      lab.create_entity { name = "entity-ghost", inner_name = e.name, position = p, direction = e.direction,
        force = design.force_index }
    end
  end
end

-- The anchor is the mod's own and has no place in the picture.
local function drop_anchor(ghosts)
  for _, ghost in pairs(ghosts) do
    if ghost.valid and ghost.type == "entity-ghost" and ghost.ghost_name == const.ANCHOR then ghost.destroy() end
  end
end

-- Builds (or rebuilds) the picture of a design's current version. Returns
-- its cell, or nil when the design cannot be stamped.
function gallery.build(design, stamp_stack)
  local prepared = design.prepared
  if not (prepared and prepared.ok and stamp_stack and stamp_stack.valid_for_read) then
    gallery.remove(design.id)
    return nil
  end
  local store = storage.gallery
  local lab = labs.surface(const.GALLERY_SURFACE)
  store.surface_index = lab.index
  -- Everything the copy covers, markers included (prepare.lua).
  local whole, bounds = prepared.reach or prepared.bounds, prepared.bounds
  local cell = cell_for(lab, store, design.id, whole.right - whole.left, whole.bottom - whole.top)
  local box = cell_box(cell)
  labs.generate(lab, box, design.force_index)
  clear(lab, box)
  local corner = { x = cell.left + MARGIN + bounds.left - whole.left, y = MARGIN + bounds.top - whole.top }
  local position = placement.at_corner(prepared, corner, geometry.NORTH)
  local built = stamp_stack.build_blueprint {
    surface = lab, force = design.force_index, position = position, direction = geometry.NORTH,
    build_mode = defines.build_mode.forced, raise_built = false,
  }
  drop_anchor(built)
  fill_missing(lab, design, prepared, position, built)
  cell.footprint = placement.footprint(prepared, position, geometry.NORTH)
  cell.version = design.version
  return cell
end

-- The picture of a design: its surface and footprint, or nil.
function gallery.view(design)
  local cell = storage.gallery and storage.gallery.cells[design.id]
  if not (cell and cell.footprint and cell.version == design.version) then return nil end
  local lab = game.get_surface(const.GALLERY_SURFACE)
  return lab and { surface = lab, footprint = cell.footprint } or nil
end

-- The gallery surface was deleted or cleared: every picture is made again
-- when next shown.
function gallery.forget_surface(surface_index)
  local store = storage.gallery
  if store and store.surface_index == surface_index then storage.gallery = { next_x = 0, cells = {}, free = {} } end
end

function gallery.remove(design_id)
  local store = storage.gallery
  local cell = store and store.cells[design_id]
  if not cell then return end
  local lab = game.get_surface(const.GALLERY_SURFACE)
  if lab then clear(lab, cell_box(cell)) end
  give_back(store, cell)
  store.cells[design_id] = nil
end

return gallery
