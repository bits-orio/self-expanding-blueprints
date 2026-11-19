-- A second remote interface, added only while the dev-only test mod
-- seb-test is active (control.lua): what the tests must reach inside the
-- mod because no script can make it happen. A record of the blueprint
-- library cannot be created from Lua, so the handlers are called here with
-- stand-ins built from plain data (functions do not cross remote.call).
-- Never part of the public interface.

local const = require("scripts.const")
local library = require("scripts.core.library")
local records = require("scripts.core.records")

-- A stand-in for a blueprint record: facts = {export, label, shelf_index,
-- record_id, preview, old_engine}. With old_engine it has no shelf or id and
-- throws on a field it lacks, as a record does on engines before 2.1.25.
local function record_of(facts)
  local record = {
    object_name = "LuaRecord", valid = true, type = "blueprint", label = facts.label or "",
    is_preview = facts.preview == true, cost_to_build = {},
    export_record = function() return facts.export end,
    get_blueprint_entity_count = function() return 1 end,
  }
  if not facts.old_engine then
    record.shelf_index, record.record_id = facts.shelf_index, facts.record_id
    return record
  end
  return setmetatable(record, { __index = function(_, key) error("LuaRecord doesn't contain key " .. key) end })
end

local function id_of(design, why)
  return design and design.id, why
end

remote.add_interface(const.MOD .. "-test", {
  record_key = function(facts) return records.key(record_of(facts)) end,
  -- As the window's add button does for a held library entry.
  register_record = function(force_index, facts)
    return id_of(records.register(force_index, record_of(facts)))
  end,
  -- The design the add button would offer to update for it.
  design_for_record = function(force_index, facts)
    return id_of(records.design_for(force_index, record_of(facts)))
  end,
  follow_record = function(force_index, facts)
    return id_of(records.follow(force_index, record_of(facts)))
  end,
  -- on_gui_closed as the engine raises it for a library record.
  close_record = function(player_index, facts)
    records.on_closed({ player_index = player_index, record = facts and record_of(facts) or nil })
  end,
  link_of = function(force_index, design_id)
    local design = library.get(force_index, design_id)
    return design and design.record
  end,
})
