-- records.lua: blueprints of the blueprint library.
-- No script can create a library record, so the mod's handlers are called
-- through its test seam (scripts/remote/test_seam.lua) with stand-ins; the
-- real thing is on dev/PLAYTEST.md.
--   entry:    a design registered from a library entry remembers it by
--             shelf and id: the entry held again under a new label is that
--             design's next version, an entry of another shelf or with a
--             label never seen on it is not
--   closed:   an entry closed after an edit is noticed once; a preview is
--             not read
--   older:    a record without shelf and id (engines before 2.1.25) is
--             told apart by its label alone, as ever

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "records" }

local SEAM = rig.REMOTE .. "-test"
local CELL = { rig.panel(1.5, 1.5), rig.panel(4.5, 1.5) }
local GAME_SHELF = 65536

local function seam(fn, ...)
  return remote.call(SEAM, fn, ...)
end

local function force_index()
  return game.forces[rig.FORCE].index
end

local function facts(label, entities, more)
  local out = { label = label, export = rig.blueprint(entities, { label = label }), shelf_index = GAME_SHELF, record_id = 7 }
  for k, v in pairs(more or {}) do out[k] = v end
  return out
end

local function version_of(id)
  for _, row in ipairs(rig.call("list_designs", rig.FORCE)) do
    if row.id == id then return row.version end
  end
end

local function entry()
  local f = force_index()
  local first = facts("Record cell", CELL)
  check.eq("records an entry's key is its shelf and id", seam("record_key", first), GAME_SHELF .. ":7")
  local id, created = seam("register_record", f, first)
  check.truthy("records an entry registers", id, created)
  check.eq("records the design remembers its entry", (seam("link_of", f, id) or {}).key, GAME_SHELF .. ":7")
  check.eq("records the entry held again is its design", seam("design_for_record", f, first), id)
  check.eq("records the same id on another shelf is another entry",
    seam("design_for_record", f, facts("Record cell", CELL, { shelf_index = 1 })), nil)
  -- A label never seen on the entry: it may be another user's library.
  local stranger = facts("Record stranger", { rig.panel(1.5, 1.5) })
  check.eq("records an unseen label is not trusted", seam("design_for_record", f, stranger), nil)
  return id, first
end

local function closed(id, first)
  local f = force_index()
  check.eq("records an unchanged entry closed is no news", seam("follow_record", f, first), nil)
  local edited = facts("Record cell big", { rig.panel(1.5, 1.5), rig.panel(4.5, 1.5), rig.panel(7.5, 1.5) })
  local preview = facts("Record cell big", CELL, { preview = true })
  preview.export = edited.export
  check.eq("records a preview is not read", seam("follow_record", f, preview), nil)
  check.eq("records an edited entry closed is noticed", seam("follow_record", f, edited), id)
  check.eq("records and noticed only once", seam("follow_record", f, edited), nil)
  check.eq("records the entry under its new label is still its design", seam("design_for_record", f, edited), id)
  local again, created = seam("register_record", f, edited)
  check.same("records it registers as that design's next version", { again, created, version_of(id) }, { id, false, 2 })
  -- A version from anything else lets the entry go.
  rig.design(CELL, "Record cell")
  check.eq("records a version from a string lets the entry go", seam("design_for_record", f, edited), nil)
  -- With a player (test mode), the engine's event itself: no record, a record nobody knows.
  if game.get_player(1) then
    seam("close_record", 1, nil)
    seam("close_record", 1, facts("Record nobody", CELL, { record_id = 99 }))
    check.pass("records on_gui_closed takes an event without a record and an unknown one")
  end
end

local function older()
  local f = force_index()
  local old = facts("Record old", CELL, { old_engine = true })
  check.eq("records an older engine's record has no key", seam("record_key", old), nil)
  local id, created = seam("register_record", f, old)
  check.same("records it registers by its label", { id ~= nil, created }, { true, true })
  check.eq("records and remembers no entry", seam("link_of", f, id), nil)
  check.eq("records closing it is no news", seam("follow_record", f, old), nil)
  local again, new = seam("register_record", f, old)
  check.same("records held again its label makes the next version", { again, new }, { id, false })
end

function case.setup()
  local id, first = entry()
  closed(id, first)
  older()
end

return case
