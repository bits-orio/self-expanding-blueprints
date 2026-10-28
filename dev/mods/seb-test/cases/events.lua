-- events.lua: the custom events reach subscribers. The other cases cause
-- them: completions and finished projects everywhere, blocked sockets at the
-- fill's water, a materials wait in gates, retirements in fill and tracking.

local check = require("lib.check")

local case = { name = "events" }

local EXPECTED = {
  "on_instance_completed", "on_project_finished", "on_instance_blocked",
  "on_materials_missing", "on_instance_retired",
}

function case.setup()
  storage.event_counts = {}
end

function case.on_event(name, payload)
  local counts = storage.event_counts
  if not counts then return end
  counts[name] = (counts[name] or 0) + 1
  if name == "on_instance_completed" and type(payload.instance_id) ~= "number" then
    storage.bad_payload = true
  end
end

local function verify()
  for _, name in ipairs(EXPECTED) do
    check.truthy("events " .. name .. " raised", (storage.event_counts[name] or 0) > 0,
      check.show(storage.event_counts))
  end
  check.truthy("events completed payload names the instance", not storage.bad_payload)
end

case.checks = { [8400] = verify }

return case
