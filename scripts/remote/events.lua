-- Custom event ids, generated once per session at control.lua load. Ids are
-- regenerated every session and must never be stored; other mods resolve
-- them through the remote interface's get_event_id.

return {
  on_instance_completed = script.generate_event_name(),
  on_instance_blocked = script.generate_event_name(),
  on_instance_stalled = script.generate_event_name(),
  on_instance_retired = script.generate_event_name(),
  on_project_finished = script.generate_event_name(),
  on_materials_missing = script.generate_event_name(),
}
