-- The AI Agent Bridge write tools are off by default; the tests need them on.
data.raw["bool-setting"]["seb-agent-write-tools"].default_value = true

-- Every case shares one force, so the per-team limits (D45) are off by
-- default here; cases.limits gives its own forces tight ones through the
-- remote interface's set_limits. The whole server's time (seb-work-per-tick)
-- is off too, as no set_limits reaches it: cases.fix_server says how to run
-- its checks with it on. A headless run charts nothing (charting waits for a
-- connected player), so builders may use any generated land.
for _, name in ipairs({
  "seb-max-projects-per-force", "seb-max-building-per-force", "seb-max-plans-per-force",
  "seb-max-designs-per-force", "seb-max-design-parts", "seb-max-builders-per-force", "seb-work-per-force",
  "seb-work-per-tick",
}) do
  data.raw["int-setting"][name].default_value = 0
end
data.raw["bool-setting"]["seb-builders-charted-only"].default_value = false
