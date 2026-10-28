-- Map settings for server admins (DESIGN.md section 6, Multi-Team Support:
-- "admins get map settings for active projects and ghosts in flight per
-- team"; D44-D46: limits per team, each team's share of server time and a
-- cap on the whole server's, so a team's load slows its own growth first
-- and no team can slow the game for the others for long). One piece of
-- work still runs in a single tick: DESIGN.md "Sharing a server" says what
-- is not bounded. Zero means no limit. The remote interface can override
-- any per-team limit for one force (set_limits, scripts/core/limits.lua).
data:extend({
  {
    type = "int-setting", name = "seb-max-projects-per-force", setting_type = "runtime-global",
    default_value = 20, minimum_value = 0, order = "a",
  },
  {
    type = "int-setting", name = "seb-max-building-per-force", setting_type = "runtime-global",
    default_value = 100, minimum_value = 0, order = "b",
  },
  {
    type = "int-setting", name = "seb-max-plans-per-force", setting_type = "runtime-global",
    default_value = 3, minimum_value = 0, order = "c",
  },
  {
    type = "int-setting", name = "seb-max-designs-per-force", setting_type = "runtime-global",
    default_value = 100, minimum_value = 0, order = "d",
  },
  {
    type = "int-setting", name = "seb-max-design-parts", setting_type = "runtime-global",
    default_value = 5000, minimum_value = 0, order = "e",
  },
  {
    type = "int-setting", name = "seb-max-builders-per-force", setting_type = "runtime-global",
    default_value = 50, minimum_value = 0, order = "f",
  },
  -- D43: nothing a player starts makes the game generate map; builders keep
  -- to charted land like the grow window, unless this is off.
  {
    type = "bool-setting", name = "seb-builders-charted-only", setting_type = "runtime-global",
    default_value = true, order = "f-a",
  },
  -- Microseconds of estimated work per tick (D44, scripts/core/budget.lua).
  {
    type = "int-setting", name = "seb-work-per-force", setting_type = "runtime-global",
    default_value = 500, minimum_value = 0, maximum_value = 16000, order = "g",
  },
  -- The same for the whole server, every team together, taken in turns
  -- (scripts/core/server_budget.lua).
  {
    type = "int-setting", name = "seb-work-per-tick", setting_type = "runtime-global",
    default_value = 4000, minimum_value = 0, order = "g-a",
  },
  {
    type = "int-setting", name = "seb-idle-robot-share", setting_type = "runtime-global",
    default_value = 0, minimum_value = 0, maximum_value = 100, order = "h",
  },
  -- AI Agent Bridge write tools are opt-in (DESIGN.md section 6).
  {
    type = "bool-setting", name = "seb-agent-write-tools", setting_type = "runtime-global",
    default_value = false, order = "i",
  },
})
