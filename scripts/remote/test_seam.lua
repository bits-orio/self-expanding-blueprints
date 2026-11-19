-- A second remote interface, added only while a dev-only mod that names
-- itself in control.lua is active (seb-test, or the drag world of
-- dev/mp-drag.sh): what the tests must reach inside the mod because no
-- script can make it happen. A record of the blueprint library cannot be
-- created from Lua and a drag of the area tool needs a hand on the mouse, so
-- the handlers are called here with stand-ins built from plain data
-- (functions do not cross remote.call). Never part of the public interface.

local const = require("scripts.const")
local library = require("scripts.core.library")
local records = require("scripts.core.records")
local registry = require("scripts.core.registry")
local fill_preview = require("scripts.fill_preview")
local tool = require("scripts.tool")

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

-- The players a render object is drawn for, as indexes; empty means everyone.
local function seen_by(object)
  local indexes = {}
  for _, player in pairs(object.players or {}) do indexes[#indexes + 1] = player.index end
  return indexes
end

-- What the player's fill preview shows, as plain data; nil when nothing.
local function shown(player_index)
  local preview = registry.player(player_index).fill_preview
  if not (preview and preview.box.valid and preview.text.valid) then return nil end
  local a, b = preview.box.left_top.position, preview.box.right_bottom.position
  return {
    left = a.x, top = a.y, right = b.x, bottom = b.y, text = preview.text.text,
    green = preview.box.color.g > preview.box.color.r, box_id = preview.box.id,
    box_players = seen_by(preview.box), text_players = seen_by(preview.text),
  }
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
  fill_plan = function(force_index, design_id, where)
    return fill_preview.plan(library.get(force_index, design_id).prepared, where)
  end,
  -- A preselection event of the area tool held for `design_id`.
  drag = function(event, design_id)
    registry.player(event.player_index).tool_design = design_id
    event.item = const.TOOL
    fill_preview.on_changed(event)
    return shown(event.player_index)
  end,
  end_drag = function(player_index)
    fill_preview.on_ended({ player_index = player_index })
    return shown(player_index)
  end,
  -- What a real drag shows right now (dev/mp-drag.sh reads it every tick).
  preview = shown,
  -- The area tool for `design_id` in the player's hand, as the window's
  -- Fill an area button gives it.
  hold_area_tool = function(player_index, design_id)
    local player = game.get_player(player_index)
    registry.player(player_index).selected_design = design_id
    return tool.give_area(player)
  end,
})
