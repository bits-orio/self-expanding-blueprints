-- limits_reads.lua: what taking a request costs a builder's team (region 92).
-- Written when the griefing-mitigation work was put together; see DESIGN.md
-- D44. A builder copies its whole input into Lua once per request, so a wire
-- carrying hundreds of signals costs its team by its size: on a share of
-- 1 µs a tick, one Sense taken with every item and virtual signal on the
-- input leaves the team waiting, and its next plan waits its turn.

local check = require("lib.check")
local rig = require("lib.rig")
local builders = require("lib.builders")

local case = { name = "limits_reads" }

local REGION = 92

-- One of every item and plain virtual signal, besides the request's own.
local function every_signal()
  local fields, items = { ["seb-sense"] = 1, ["seb-sense-entities"] = 1 }, {}
  for name, proto in pairs(prototypes.item) do
    if not proto.hidden and not proto.parameter and name:find("^seb") == nil then items[name] = 1 end
  end
  for name, proto in pairs(prototypes.virtual_signal) do
    if not proto.special and name:find("^seb") == nil and name:find("^signal%-[XYWHR]$") == nil then fields[name] = 1 end
  end
  return fields, items
end

function case.setup(surface)
  local o = rig.region(REGION)
  rig.floor(surface, rig.box(o, -20, -20, 20, 40))
  local force = rig.own_force("seb-limits-reads")
  -- Registered before the force has a share: only the request is charged.
  local design = rig.call("register_design", force, rig.blueprint({ rig.panel(1.5, 1.5) }, { label = "Reads" }))
  local _, program = builders.place(surface, rig.offset(o, 0.5, 0.5), force)
  builders.send(program, every_signal())
  rig.call("set_limits", force, { work = 1 })
  storage.limits_reads = { force = force, design = design, at = rig.offset(o, 0.5, 20.5) }
end

-- The builder took its request at its first read (tick 12).
function case.start(surface)
  local r = storage.limits_reads
  r.plan = rig.call("start_project", { force = r.force, surface = surface, design = r.design, position = r.at, dry_run = true })
end

local function waited_busy(history)
  for _, entry in ipairs(history or {}) do
    if entry.kind == "waiting" and entry.reason == "busy" then return true end
  end
  return false
end

case.checks = {
  [120] = function()
    local plan = rig.call("get_project", storage.limits_reads.plan)
    check.truthy("limits_reads a request taken with hundreds of signals is charged by them: the team's plan waits its turn",
      plan and waited_busy(plan.history), check.show(plan and plan.history))
  end,
}

return case
