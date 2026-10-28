-- library.lua: designs per force, versions, refusals.

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "library" }

local PANEL = { { name = "solar-panel", position = { x = 1.5, y = 1.5 } } }

local function row_of(force, id)
  for _, row in ipairs(rig.call("list_designs", force)) do
    if row.id == id then return row end
  end
end

local function book_string()
  local inventory = game.create_inventory(1)
  inventory[1].set_stack { name = "blueprint-book" }
  local inner = inventory[1].get_inventory(defines.inventory.item_main)
  inner.insert { name = "blueprint" }
  inner[1].set_blueprint_entities(PANEL)
  local text = inventory[1].export_stack()
  inventory.destroy()
  return text
end

function case.setup()
  local id, created = rig.design(PANEL, "Library panel")
  check.truthy("library register", id)
  check.eq("library register is new", created, true)
  local again, created_again = rig.design({ PANEL[1], { name = "small-electric-pole", position = { x = 3.5, y = 0.5 } } },
    "Library panel")
  check.eq("library same name is the same design", again, id)
  check.eq("library same name is not new", created_again, false)
  local row = row_of(rig.FORCE, id)
  check.eq("library same name bumps the version", row and row.version, 2)
  check.eq("library prepared ok", row and row.ok, true)

  local bad, reason = rig.call("register_design", rig.FORCE, "0not-a-blueprint")
  check.eq("library refuses garbage", bad, nil)
  check.eq("library garbage reason", reason, "invalid-design")

  -- The library as a book, added to another force: the same designs.
  local exported = rig.call("export_library", rig.FORCE)
  local other = game.create_force("seb-test-library")
  local ids = exported and rig.call("register_design", other, exported)
  check.eq("library export adds back as many designs", ids and #ids, #rig.call("list_designs", rig.FORCE))
  -- A book string registers every blueprint in it and returns their ids.
  local book = rig.call("register_design", rig.FORCE, book_string())
  check.eq("library registers a book string's blueprints", type(book) == "table" and #book, 1)

  local two = rig.design({ PANEL[1], { name = "seb-entry", position = { x = 0.5, y = 0.5 } },
    { name = "seb-entry", position = { x = 2.5, y = 0.5 } } }, "Two entries")
  local two_row = row_of(rig.FORCE, two)
  check.eq("library two entries is not stampable", two_row and two_row.ok, false)
  check.eq("library two entries error", two_row and two_row.error, "many-entries")

  local failed, failure = rig.design({ PANEL[1], { name = "seb-entry", position = { x = 0.5, y = 0.5 } },
    { name = "seb-entry", position = { x = 2.5, y = 0.5 } } }, "Library panel")
  check.eq("library failed update refused", failed, nil)
  check.eq("library failed update reason", failure, "many-entries")
  local kept = row_of(rig.FORCE, id)
  check.same("library failed update keeps the working version", kept and { kept.version, kept.ok }, { 2, true })

  local unnamed = rig.call("register_design", rig.FORCE, rig.blueprint(PANEL))
  check.truthy("library unlabelled gets a name", (row_of(rig.FORCE, unnamed) or {}).name ~= nil)

  local other = game.create_force("seb-test-other")
  local theirs = rig.call("register_design", other, rig.blueprint(PANEL, { label = "Library panel" }))
  check.truthy("library other force gets an id of its own", theirs and theirs ~= id, check.show(theirs))
  check.eq("library other force sees only its own", #rig.call("list_designs", other), 1)
  check.eq("library ids never resolve in another force", row_of(rig.FORCE, theirs), nil)
  local lab = game.get_surface("seb-calibration")
  check.same("library calibration lab hidden from every force", lab and {
    game.forces[rig.FORCE].get_surface_hidden(lab), other.get_surface_hidden(lab),
  }, { true, true })
end

return case
