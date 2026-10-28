-- fix_designs.lua: books, sockets and registration costs (regions 150-159).
-- Written by the second griefing round (DESIGN.md D44, D45).
--   books:    a book whose walk looks at more than 1,000 children (empty
--             blueprints and inner books count) is refused whole with
--             book-too-big, and nothing of it is registered; one of exactly
--             1,000 registers (the window's path is covered in a scratch run)
--   sockets:  65 drawn sockets are refused (too-many-sockets), as a new
--             design or as a new version; 64 register
--   tiles:    the part cap counts tiles, read from the bill of materials,
--             and not an entity's module requests
--   sensors:  2,500 ore sensors beside 2,500 lamps register at once (INFO)
--   charged:  registering costs its fixed part too (calibration, picture):
--             after a tiny new version the team's next plan waits its turn

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "fix_designs" }

local REGION = 150
local FORCE = "seb-fix-designs"
local D = defines.direction

local function lamp(x, y)
  return { name = "small-lamp", position = { x = x, y = y } }
end

local function register(entities, label, opts)
  opts = opts or {}
  opts.label = label
  return rig.call("register_design", FORCE, rig.blueprint(entities, opts))
end

local function designs()
  return #rig.call("list_designs", FORCE)
end

local function row_of(id)
  for _, row in ipairs(rig.call("list_designs", FORCE)) do
    if row.id == id then return row end
  end
end

-- `empty` empty blueprints and one set up, in `book` (an inventory stack).
local function fill(book, empty)
  book.set_stack { name = "blueprint-book" }
  local slots = book.get_inventory(defines.inventory.item_main)
  if empty > 0 then slots.insert { name = "blueprint", count = empty } end
  slots.insert { name = "blueprint" }
  slots[empty + 1].set_blueprint_entities { { entity_number = 1, name = "small-lamp", position = { 0.5, 0.5 } } }
  slots[empty + 1].label = "Book lamp"
end

-- A book string of `empty` empty blueprints and one set up; with `nested`,
-- all of that inside one inner book.
local function book_string(empty, nested)
  local inventory = game.create_inventory(2)
  fill(inventory[1], empty)
  if nested then
    inventory[2].set_stack { name = "blueprint-book" }
    inventory[2].get_inventory(defines.inventory.item_main).insert(inventory[1])
    inventory[1].swap_stack(inventory[2])
  end
  local text = inventory[1].export_stack()
  inventory.destroy()
  return text
end

local function books_case()
  local before = designs()
  local p = helpers.create_profiler()
  local over, why = rig.call("register_design", FORCE, book_string(1000))
  p.stop()
  log({ "", "SEB_TEST INFO fix_designs a book of 1,001 children refused in ", p })
  check.same("fix_designs a book of 1,001 children is refused", { over, why }, { nil, "book-too-big" })
  check.eq("fix_designs a refused book registers nothing", designs(), before)
  local nested, nested_why = rig.call("register_design", FORCE, book_string(999, true))
  check.same("fix_designs an inner book counts as a child", { nested, nested_why }, { nil, "book-too-big" })
  local ids = rig.call("register_design", FORCE, book_string(999))
  check.eq("fix_designs a book of exactly 1,000 children registers", type(ids) == "table" and #ids, 1)
end

local function sockets(n)
  local list = { lamp(0.5, 0.5) }
  for i = 1, n do list[#list + 1] = rig.socket(i - 0.5, -0.5, D.north) end
  return list
end

local function sockets_case()
  local before = designs()
  local over, why = register(sockets(65), "Socket rake")
  check.same("fix_designs 65 sockets are refused", { over, why }, { nil, "too-many-sockets" })
  check.eq("fix_designs a refused rake is not kept", designs(), before)
  local id = register(sockets(64), "Socket rake")
  check.truthy("fix_designs 64 sockets register", id and (row_of(id) or {}).ok, check.show(id))
  local grown, grown_why = register(sockets(65), "Socket rake")
  check.same("fix_designs a version with 65 sockets is refused", { grown, grown_why }, { nil, "too-many-sockets" })
  check.eq("fix_designs a refused version keeps the design", (row_of(id) or {}).version, 1)
end

local function tiles(n)
  local list = {}
  for i = 1, n do list[i] = { name = "stone-path", position = { x = i - 1, y = 3 } } end
  return list
end

-- An assembler asking for two modules, with nine floor tiles: ten parts.
local MODULES = {
  name = "assembling-machine-2", position = { x = 1.5, y = 1.5 },
  items = { { id = { name = "speed-module" }, items = { in_inventory = {
    { inventory = defines.inventory.crafter_modules, stack = 0, count = 1 },
    { inventory = defines.inventory.crafter_modules, stack = 1, count = 1 },
  } } } },
}

local function tiles_case()
  rig.call("set_limits", FORCE, { design_parts = 10 })
  local id = register({ MODULES }, "Tiled machine", { tiles = tiles(9) })
  check.truthy("fix_designs ten parts with tiles and module requests register", id and (row_of(id) or {}).ok,
    check.show(id))
  local over, why = register({ lamp(0.5, 0.5) }, "Tiled lamp", { tiles = tiles(10) })
  check.same("fix_designs tiles count toward the part cap", { over, why }, { nil, "design-too-big" })
  rig.call("set_limits", FORCE, { design_parts = 0 })
end

local function sensors_case()
  local list = {}
  for i = 0, 2499 do list[#list + 1] = lamp(i % 100 + 0.5, math.floor(i / 100) + 0.5) end
  for i = 0, 2499 do
    list[#list + 1] = { name = "seb-sensor", position = { x = i % 100 + 0.5, y = math.floor(i / 100) + 60.5 } }
  end
  local text = rig.blueprint(list, { label = "Sensor field" })
  local p = helpers.create_profiler()
  local id = rig.call("register_design", FORCE, text)
  p.stop()
  log({ "", "SEB_TEST INFO fix_designs 2,500 sensors beside 2,500 lamps registered in ", p })
  check.truthy("fix_designs a sensor-heavy design registers", id and (row_of(id) or {}).ok, check.show(id))
end

function case.setup(surface)
  rig.own_force(FORCE)
  rig.floor(surface, rig.box(rig.region(REGION), -60, -60, 60, 60))
  books_case()
  sockets_case()
  tiles_case()
  sensors_case()
  storage.fix_designs_tiny = register({ lamp(0.5, 0.5) }, "Tiny")
  -- From here on the team has a small share: a registration's fixed cost
  -- (1,500 µs) is more than it saves up (600 µs), its string and part not.
  rig.call("set_limits", FORCE, { work = 10 })
end

case.checks = {
  [600] = function(surface)
    register({ lamp(0.5, 0.5), lamp(1.5, 0.5) }, "Tiny")
    storage.fix_designs_plan = rig.call("start_project", {
      force = FORCE, surface = surface, design = storage.fix_designs_tiny, position = rig.region(REGION),
      dry_run = true, charted_only = false,
    })
  end,
  [660] = function()
    local plan = rig.call("get_project", storage.fix_designs_plan) or {}
    check.same("fix_designs a registration's fixed cost is charged: the next plan waits its turn",
      { plan.count, plan.gate }, { 0, "busy" })
  end,
  [1200] = function()
    local plan = rig.call("get_project", storage.fix_designs_plan) or {}
    check.truthy("fix_designs the plan goes on once the team's share is back", (plan.count or 0) > 0, check.show(plan))
  end,
}

return case
