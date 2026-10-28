-- limits_designs.lua: design caps and registration cost (regions 70-79).
-- Written by the griefing-mitigation work; see DESIGN.md D43-D45.
--   far:      a design whose parts sit 4,000 tiles from their blueprint
--             origin calibrates on no more lab than a near one, and its
--             copies land exactly as the near one's do, in every direction
--   too big:  more parts than design_parts, or wider than MAX_DESIGN_SPAN
--             (markers included), is refused before any lab work, new
--             design or new version alike
--   cap:      with designs = 3 the fourth new design is refused, a new
--             version of the first is not
--   gallery:  a released team's picture cell, and the cell a design
--             outgrew, are reused before the strip grows
--   sparse:   two lamps 511 tiles apart need hundreds of lab chunks made
--             for their picture; the team pays for them, so its next plan
--             waits for its share of server time
--   refused:  a blueprint refused as too big still cost its export and
--             import: the team pays by its string's length, and waits too

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "limits_designs" }

local REGION = 70
local D = defines.direction
local SPAN = 512   -- const.MAX_DESIGN_SPAN

local function lamp(x, y)
  return { name = "small-lamp", position = { x = x, y = y } }
end

local function lamps(n)
  local list = {}
  for i = 1, n do list[i] = lamp(i - 0.5, 0.5) end
  return list
end

local function register(force, entities, label)
  return rig.call("register_design", force, rig.blueprint(entities, { label = label }))
end

local function generated(name)
  local surface = game.get_surface(name)
  local n = 0
  for chunk in (surface and surface.get_chunks() or function() end) do
    if surface.is_chunk_generated(chunk) then n = n + 1 end
  end
  return n
end

local function row_of(force, id)
  for _, row in ipairs(rig.call("list_designs", force)) do
    if row.id == id then return row end
  end
end

-- Where a stamp's ghosts landed, relative to its build position.
local function layout(surface, force, design, at, direction)
  local id, reason = rig.call("stamp", {
    force = force, surface = surface, design = design, build_position = at, direction = direction,
  })
  if not id then return reason end
  local box = { left = at.x - 8, top = at.y - 8, right = at.x + 8, bottom = at.y + 8 }
  local rows = {}
  for _, row in ipairs(rig.ghost_rows(surface, box)) do rows[#rows + 1] = { row[1], row[2] - at.x, row[3] - at.y } end
  table.sort(rows, function(p, q) return p[2] < q[2] or (p[2] == q[2] and p[3] < q[3]) end)
  return rows
end

local function far_case(surface)
  local force = rig.own_force("seb-limits-far")
  local o = rig.region(REGION)
  rig.floor(surface, rig.box(o, -10, -10, 110, 30))
  local near = register(force, { lamp(0.5, 0.5), lamp(3.5, 1.5) }, "Near pair")
  local before = generated("seb-calibration")
  local far = register(force, { lamp(4000.5, 0.5), lamp(4003.5, 1.5) }, "Far pair")
  check.truthy("limits_designs far design registers", far and (row_of(force, far) or {}).ok, check.show(far))
  check.eq("limits_designs far design generates no more lab than a near one", generated("seb-calibration") - before, 0)
  for i, d in ipairs({ D.north, D.east, D.south, D.west }) do
    local x = 20 * i
    local want = layout(surface, force, near, rig.offset(o, x, 0), d)
    check.same("limits_designs far copy lands as the near one, direction " .. d,
      layout(surface, force, far, rig.offset(o, x, 15), d), want)
  end
  -- The stamp centres the pair's 4 x 2 tiles on the build position.
  local alone = layout(surface, force, far, rig.offset(o, 100, 0), D.north)
  check.same("limits_designs far copy lands where expected", alone,
    { { "small-lamp", -1.5, -0.5 }, { "small-lamp", 1.5, 0.5 } })
end

local function too_big_case()
  local force = rig.own_force("seb-limits-parts")
  rig.call("set_limits", force, { design_parts = 10 })
  local over, why = register(force, lamps(11), "Eleven")
  check.same("limits_designs more parts than allowed refused", { over, why }, { nil, "design-too-big" })
  local ten = register(force, lamps(10), "Ten")
  check.truthy("limits_designs parts at the limit register", ten and (row_of(force, ten) or {}).ok, check.show(ten))
  local grown, grown_why = register(force, lamps(11), "Ten")
  check.same("limits_designs a too big version refused", { grown, grown_why }, { nil, "design-too-big" })
  check.eq("limits_designs a too big version keeps the design", (row_of(force, ten) or {}).version, 1)
  check.eq("limits_designs a refused design is not kept", #rig.call("list_designs", force), 1)

  local wide = rig.own_force("seb-limits-wide")
  local lab = generated("seb-calibration")
  local too_wide, wide_why = register(wide, { lamp(0.5, 0.5), lamp(SPAN + 0.5, 0.5) }, "Too wide")
  check.same("limits_designs wider than the span refused", { too_wide, wide_why }, { nil, "design-too-big" })
  check.eq("limits_designs a refused design makes no lab", generated("seb-calibration"), lab)
  local marked, marked_why = register(wide, { lamp(0.5, 0.5), rig.socket(0.5, SPAN + 0.5, D.south) }, "Marked")
  check.same("limits_designs markers count in the span", { marked, marked_why }, { nil, "design-too-big" })
  local widest = register(wide, { lamp(0.5, 0.5), lamp(SPAN - 0.5, 0.5) }, "Widest")
  check.truthy("limits_designs the span itself registers", widest and (row_of(wide, widest) or {}).ok,
    check.show(widest))
end

local function cap_case()
  local force = rig.own_force("seb-limits-cap")
  rig.call("set_limits", force, { designs = 3 })
  local first = register(force, { lamp(0.5, 0.5) }, "Cap 1")
  register(force, { lamp(0.5, 0.5) }, "Cap 2")
  register(force, { lamp(0.5, 0.5) }, "Cap 3")
  local fourth, why = register(force, { lamp(0.5, 0.5) }, "Cap 4")
  check.same("limits_designs the fourth new design refused", { fourth, why }, { nil, "too-many-designs" })
  local again, created = register(force, { lamp(0.5, 0.5), lamp(1.5, 0.5) }, "Cap 1")
  check.same("limits_designs a new version is never refused", { again, created }, { first, false })
  check.eq("limits_designs the new version counts", (row_of(force, first) or {}).version, 2)
  check.eq("limits_designs still three designs", #rig.call("list_designs", force), 3)
end

-- The picture ghosts of a force's one design on the gallery, sorted.
local function picture(force)
  local gallery = game.get_surface("seb-gallery")
  local rows = {}
  for _, g in pairs(gallery and gallery.find_entities_filtered { force = force, type = "entity-ghost" } or {}) do
    rows[#rows + 1] = { g.ghost_name, g.position.x, g.position.y }
  end
  table.sort(rows, function(a, b) return a[2] < b[2] or (a[2] == b[2] and a[3] < b[3]) end)
  return rows
end

local PAIR = { rig.panel(1.5, 1.5), rig.panel(4.5, 1.5) }
local WIDE = { rig.panel(1.5, 1.5), rig.panel(24.5, 1.5) }

local function gallery_case()
  local released = remote.call("mts-v1", "get_event_id", "on_team_released")
  local a, b = rig.own_force("seb-limits-gallery-a"), rig.own_force("seb-limits-gallery-b")
  register(a, PAIR, "Gallery pair")
  local was, chunks = picture(a), generated("seb-gallery")
  script.raise_event(released, { force_name = a })
  check.eq("limits_designs a released team's picture goes", #picture(a), 0)
  register(b, PAIR, "Gallery pair")
  check.same("limits_designs a freed cell is reused", picture(b), was)
  check.eq("limits_designs a reused cell needs no new gallery", generated("seb-gallery"), chunks)

  local c, d, e = rig.own_force("seb-limits-gallery-c"), rig.own_force("seb-limits-gallery-d"),
    rig.own_force("seb-limits-gallery-e")
  register(c, PAIR, "Gallery grows")
  was = picture(c)
  register(e, PAIR, "Gallery next")
  register(c, WIDE, "Gallery grows")
  chunks = generated("seb-gallery")
  register(d, PAIR, "Gallery after")
  check.same("limits_designs an outgrown cell is reused", picture(d), was)
  check.eq("limits_designs an outgrown cell needs no new gallery", generated("seb-gallery"), chunks)
end

-- A few parts far apart: the picture cell's chunks are charged to the team.
local function sparse_case(surface)
  local force = rig.own_force("seb-limits-sparse")
  rig.call("set_limits", force, { work = 500 })
  local id = register(force, { lamp(0.5, 0.5), lamp(SPAN - 0.5, SPAN - 0.5) }, "Sparse")
  check.truthy("limits_designs a sparse wide design registers", id and (row_of(force, id) or {}).ok, check.show(id))
  storage.limits_designs_plan = rig.call("start_project", {
    -- Far from every region: its outline is the width of the design.
    force = force, surface = surface, design = id, position = { x = -3000, y = 1000 }, dry_run = true,
  })
end

-- A refusal is charged too: by the length of the blueprint's string.
local function refused_case(surface)
  local force = rig.own_force("seb-limits-refused")
  local id = register(force, { lamp(0.5, 0.5) }, "Refused small")
  rig.call("set_limits", force, { design_parts = 10, work = 1 })
  local big, why = register(force, lamps(200), "Refused big")
  check.same("limits_designs a big blueprint is refused", { big, why }, { nil, "design-too-big" })
  storage.limits_designs_refused = rig.call("start_project", {
    force = force, surface = surface, design = id, position = rig.offset(rig.region(REGION), 200, 200), dry_run = true,
  })
end

local function waited_busy(history)
  for _, entry in ipairs(history or {}) do
    if entry.kind == "waiting" and entry.reason == "busy" then return true end
  end
  return false
end

function case.setup(surface)
  far_case(surface)
  too_big_case()
  cap_case()
  gallery_case()
  sparse_case(surface)
  refused_case(surface)
end

case.checks = {
  [120] = function()
    local plan = rig.call("get_project", storage.limits_designs_plan)
    check.truthy("limits_designs a sparse design's lab chunks are charged: the team's next plan waits its turn",
      plan and waited_busy(plan.history), check.show(plan and plan.history))
    local after = rig.call("get_project", storage.limits_designs_refused)
    check.truthy("limits_designs a refused registration is charged too: the team's next plan waits its turn",
      after and waited_busy(after.history), check.show(after and after.history))
  end,
}

return case
