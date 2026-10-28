-- Counts selected events while storage.watch is set; silent otherwise.
local E = {}

local NAMES = {
  "script_raised_built", "on_built_entity", "on_object_destroyed", "on_marked_for_deconstruction",
  "script_raised_destroy", "on_robot_built_entity", "on_pre_ghost_deconstructed", "on_entity_died",
  "on_cancelled_deconstruction", "on_marked_for_upgrade", "on_pre_build", "script_raised_set_tiles",
  "on_surface_created", "on_chunk_generated",
}

function E.register()
  for _, name in ipairs(NAMES) do
    script.on_event(defines.events[name], function()
      local w = storage.watch
      if w then w[name] = (w[name] or 0) + 1 end
    end)
  end
end

function E.start() storage.watch = {} end

function E.stop()
  local w = storage.watch
  storage.watch = nil
  return w or {}
end

return E
