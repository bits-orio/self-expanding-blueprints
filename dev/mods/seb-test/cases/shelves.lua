-- shelves.lua: books of books, and probes that look for buildings.
--   shelf:  a labelled book holding labelled books is no pool itself; each
--           book in it becomes one (a loose blueprint joins none)
--   export: the library comes out with a book per pool, and adding it back
--           makes the same pools and no pool of the export's own label
--   probe:  a probe asking for a small electric pole holds only where the
--           team's pole stands

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "shelves" }

local PROBE_REGION = 198
local D = defines.direction

local function blueprint_into(inner, label, entities)
  inner.insert { name = "blueprint" }
  for i = 1, #inner do
    local s = inner[i]
    if s.valid_for_read and s.is_blueprint and not s.is_blueprint_setup() then
      s.import_stack(rig.blueprint(entities, { label = label }))
      return
    end
  end
end

local function book_into(inner, label)
  inner.insert { name = "blueprint-book" }
  for i = 1, #inner do
    local s = inner[i]
    if s.valid_for_read and s.is_blueprint_book and not s.label then
      s.label = label
      return s.get_inventory(defines.inventory.item_main)
    end
  end
end

local function shelf_string()
  local inventory = game.create_inventory(1)
  local shelf = inventory[1]
  shelf.set_stack { name = "blueprint-book" }
  shelf.label = "Shelf"
  local inner = shelf.get_inventory(defines.inventory.item_main)
  local a = book_into(inner, "Pool A")
  blueprint_into(a, "Shelf one", { { name = "iron-chest", position = { x = 0.5, y = 0.5 } } })
  blueprint_into(a, "Shelf two", { { name = "wooden-chest", position = { x = 0.5, y = 0.5 } } })
  local b = book_into(inner, "Pool B")
  blueprint_into(b, "Shelf three", { { name = "steel-chest", position = { x = 0.5, y = 0.5 } } })
  blueprint_into(inner, "Shelf loose", { { name = "small-lamp", position = { x = 0.5, y = 0.5 } } })
  local text = shelf.export_stack()
  inventory.destroy()
  return text
end

-- The labels inside an exported library: {label = number of blueprints}.
local function export_books(text)
  local inventory = game.create_inventory(1)
  inventory[1].import_stack(text)
  local found = {}
  local inner = inventory[1].get_inventory(defines.inventory.item_main)
  for i = 1, #inner do
    local s = inner[i]
    if s.valid_for_read and s.is_blueprint_book then
      local n, shelf = 0, s.get_inventory(defines.inventory.item_main)
      for j = 1, #shelf do if shelf[j].valid_for_read then n = n + 1 end end
      found[s.label] = n
    end
  end
  inventory.destroy()
  return found
end

local function probe_with(filters)
  local list = {}
  for i, f in ipairs(filters) do
    list[i] = { index = i, type = f[1], name = f[2], quality = "normal", comparator = "=", count = 1 }
  end
  return { name = "seb-probe", position = { x = 1.5, y = 0.5 },
    control_behavior = { sections = { sections = { { index = 1, filters = list } } } } }
end

local PROBE = {
  name = "seb-probe", position = { x = 1.5, y = 0.5 },
  control_behavior = { sections = { sections = { { index = 1, filters = {
    { index = 1, type = "item", name = "small-electric-pole", quality = "normal", comparator = "=", count = 1 },
  } } } } },
}

function case.setup(surface)
  local ids = rig.call("register_design", rig.FORCE, shelf_string())
  check.eq("shelves a shelf registers its four blueprints", ids and #ids, 4)
  local pools = rig.call("list_pools", rig.FORCE)
  check.eq("shelves pool A holds its two", pools["Pool A"] and #pools["Pool A"], 2)
  check.eq("shelves pool B holds its one", pools["Pool B"] and #pools["Pool B"], 1)
  check.eq("shelves the shelf itself is no pool", pools["Shelf"], nil)
  local text = rig.call("export_library", rig.FORCE)
  local books = export_books(text)
  check.eq("shelves the export has a book for pool A", books["Pool A"], 2)
  check.eq("shelves the export has a book for pool B", books["Pool B"], 1)
  -- Adding the whole export back would make a new version of every design
  -- the other cases use: a small book under the export's label stands in.
  local inventory = game.create_inventory(1)
  local book = inventory[1]
  book.set_stack { name = "blueprint-book" }
  book.label = "Self-Expanding Blueprints"
  blueprint_into(book.get_inventory(defines.inventory.item_main), "Shelf exported",
    { { name = "iron-chest", position = { x = 0.5, y = 0.5 } }, { name = "small-lamp", position = { x = 1.5, y = 0.5 } } })
  rig.call("register_design", rig.FORCE, book.export_stack())
  inventory.destroy()
  check.eq("shelves the export's label is no pool", rig.call("list_pools", rig.FORCE)["Self-Expanding Blueprints"], nil)

  local o = rig.site(surface, PROBE_REGION)
  for y = 0, 1 do surface.create_entity { name = "small-electric-pole", position = { o.x + 1.5, o.y + y + 0.5 }, force = rig.FORCE } end
  -- Ghosts of a heat pipe (no network stocks one, so no robot builds them)
  -- beside three rows 20 tiles east; a real heat pipe by a fourth.
  for y = 0, 2 do
    surface.create_entity { name = "entity-ghost", inner_name = "heat-pipe", position = { o.x + 21.5, o.y + y + 0.5 }, force = rig.FORCE }
  end
  surface.create_entity { name = "heat-pipe", position = { o.x + 21.5, o.y + 3.5 }, force = rig.FORCE }
  storage.shelves = {
    design = rig.design({ { name = "iron-chest", position = { x = 0.5, y = 0.5 } }, PROBE, rig.socket(0.5, 1.5, D.south, "") },
      "Probe pole"),
    ghostly = rig.design({ { name = "iron-chest", position = { x = 0.5, y = 0.5 } },
      probe_with({ { "virtual", "seb-sense-ghosts" }, { "item", "heat-pipe" } }), rig.socket(0.5, 1.5, D.south, "") },
      "Probe pole ghost"),
  }
end

function case.start()
  local o = rig.region(PROBE_REGION)
  local id, reason = rig.call("start_project", {
    force = rig.FORCE, surface = game.surfaces.nauvis, design = storage.shelves.design, charted_only = false,
    position = { x = o.x + 0.5, y = o.y + 0.5 }, max_instances = 5,
  })
  check.truthy("shelves probe project starts", id, reason)
  storage.shelves.project = id
  local gid, why = rig.call("start_project", {
    force = rig.FORCE, surface = game.surfaces.nauvis, design = storage.shelves.ghostly, charted_only = false,
    position = { x = o.x + 20.5, y = o.y + 0.5 }, max_instances = 6,
  })
  check.truthy("shelves ghost probe project starts", gid, why)
  storage.shelves.ghost_project = gid
end

local function verify()
  local p = rig.call("get_project", storage.shelves.project)
  check.eq("shelves the probe holds beside the poles only", p and p.count, 2)
  check.eq("shelves the probe closes where no pole stands", p and p.closed.probe, 1)
  local g = rig.call("get_project", storage.shelves.ghost_project)
  check.eq("shelves a ghost-kind probe holds by the ghosts only, not the real one", g and g.count, 3)
end

case.checks = { [1500] = verify }

return case
