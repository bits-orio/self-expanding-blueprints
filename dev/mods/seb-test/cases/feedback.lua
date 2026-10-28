-- feedback.lua: what the first playtest asked for.
--   marks:     stopping a project takes every mark it drew off the map, its
--              copies' outlines included (a copy still building, an
--              incomplete one)
--   next:      a copy under construction shows where its project grows
--              next: an arrow and the next copy's dashed outline
--   far:       a first copy no robots reach still goes down, as ghosts
--   status:    a project says why it is where it is (waiting for materials,
--              no robots, stalled, finished) and keeps a short history:
--              started, waits, blocks (repeats merged), pauses, the finish
--   gallery:   every design is built once as ghosts of its force on a
--              hidden surface, for the window's pictures

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "feedback" }

local MARKS_REGION, WAIT_REGION, WATER_REGION, FAR_REGION = 30, 31, 32, 33
local D = defines.direction
local CELL = { rig.panel(1.5, 1.5) }
local NO_PANELS = { { "medium-electric-pole", 10 } }

local function start(design, at, extra)
  local params = {
    force = rig.FORCE, surface = game.surfaces.nauvis, design = design, position = at, charted_only = false,
  }
  for k, v in pairs(extra or {}) do params[k] = v end
  local id, reason = rig.call("start_project", params)
  check.truthy("feedback project starts", id, reason)
  return id
end

local function kinds(project)
  local list = {}
  for _, entry in ipairs(project and project.history or {}) do list[#list + 1] = entry.kind end
  return table.concat(list, ",")
end

local function entry_of(project, kind)
  for _, entry in ipairs(project and project.history or {}) do
    if entry.kind == kind then return entry end
  end
end

function case.setup(surface)
  local m = rig.region(MARKS_REGION)
  rig.floor(surface, rig.box(m, -60, -60, 60, 60))
  rig.network(surface, rig.offset(m, -25, -25), NO_PANELS)
  local w = rig.region(WAIT_REGION)
  rig.floor(surface, rig.box(w, -60, -60, 60, 60))
  rig.network(surface, rig.offset(w, -25, -25), NO_PANELS)
  local o = rig.site(surface, WATER_REGION)
  rig.water(surface, rig.box(o, 6, -4, 16, 16))
  rig.water(surface, rig.box(o, -4, 6, 16, 16))
  rig.floor(surface, rig.box(rig.region(FAR_REGION), -20, -20, 20, 20))
  storage.feedback = { cell = rig.design(CELL, "Feedback cell") }
  local gallery = game.get_surface("seb-gallery")
  check.truthy("feedback gallery surface exists", gallery)
  if not gallery then return end
  check.truthy("feedback gallery hidden", game.forces[rig.FORCE].get_surface_hidden(gallery))
  local panels = gallery.find_entities_filtered { ghost_name = "solar-panel" }
  check.truthy("feedback gallery holds a copy", #panels > 0)
  check.eq("feedback gallery copy is the design force's ghosts", panels[1] and panels[1].force.name, rig.FORCE)
  check.eq("feedback gallery has nothing real", gallery.count_entities_filtered { name = "solar-panel" }, 0)
  check.eq("feedback gallery has no anchors", gallery.count_entities_filtered { ghost_name = "seb-anchor" }, 0)
end

function case.start()
  local f = storage.feedback
  local m = rig.region(MARKS_REGION)
  -- Never built (no panels in the network): building, then stalled.
  f.building = start(f.cell, rig.offset(m, 0.5, 0.5), { max_instances = 1, materials = false })
  f.incomplete = start(f.cell, rig.offset(m, 0.5, 20.5), { max_instances = 1, materials = false })
  f.waiting = start(f.cell, rig.offset(rig.region(WAIT_REGION), 0.5, 0.5), { max_instances = 1 })
  f.water = start(f.cell, rig.offset(rig.region(WATER_REGION), 0.5, 0.5), { directions = { D.east, D.south } })
  f.far = start(f.cell, rig.offset(rig.region(FAR_REGION), 0.5, 0.5), { max_instances = 1 })
  f.next = start(f.cell, rig.offset(m, 40.5, 0.5), { max_instances = 3, materials = false, directions = { D.east } })
  f.capped = start(f.cell, rig.offset(m, 60.5, 0.5), { max_instances = 1, materials = false, directions = { D.east } })
end

-- East of the copy that f.next is building: where its next copy goes.
local function ahead_box()
  return rig.box(rig.region(MARKS_REGION), 41.5, -3, 48, 4)
end

local function marks_box(dy)
  return rig.box(rig.region(MARKS_REGION), -10, dy - 10, 10, dy + 10)
end

local function count(drawn)
  local n = 0
  for _, k in pairs(drawn) do n = n + k end
  return n
end

-- One ghost of the second copy is removed by hand: it comes out incomplete.
local function remove_a_ghost(surface)
  local b = marks_box(20)
  local ghost = surface.find_entities_filtered { area = { { b.left, b.top }, { b.right, b.bottom } }, type = "entity-ghost" }[1]
  check.truthy("feedback a ghost to remove", ghost)
  if ghost then ghost.destroy() end
end

local function early(surface)
  local f = storage.feedback
  check.truthy("feedback building copy is drawn", count(rig.drawn(surface, marks_box(0))) > 0)
  remove_a_ghost(surface)
  local w = rig.call("get_project", f.waiting)
  check.eq("feedback waiting level", w and w.status.level, "waiting")
  check.eq("feedback waiting reason", w and w.status.reason, "missing-materials")
  check.eq("feedback waiting item", w and w.status.item and w.status.item.name, "solar-panel")
  check.eq("feedback waiting spare count", w and w.status.item and w.status.item.have, 0)
  check.eq("feedback waiting history", kinds(w), "started,waiting")
  rig.call("pause_project", f.waiting)
  rig.call("resume_project", f.waiting)
  local ahead = rig.drawn(surface, ahead_box())
  check.eq("feedback building copy outlines its next copy", ahead.line, 4)
  check.eq("feedback building copy shows where it grows", ahead["seb-overlay-arrow"], 1)
  local capped = rig.drawn(surface, rig.box(rig.region(MARKS_REGION), 61.5, -3, 68, 4))
  check.eq("feedback no next marks once the count is reached", (capped.line or 0) + (capped["seb-overlay-arrow"] or 0), 0)
  -- No robots reach the first copy: it goes down anyway, as ghosts.
  local far = rig.call("get_project", f.far)
  check.eq("feedback out-of-reach first copy placed", far and far.count, 1)
  local far_copy = rig.instances_of(f.far)[1]
  check.eq("feedback out-of-reach first copy waits as ghosts", far_copy and far_copy.state, "building")
  check.eq("feedback out-of-reach history", kinds(far), "started")
  -- A single stamp that asks for materials still refuses where no robots reach.
  local stamped, refusal = rig.call("stamp", { force = rig.FORCE, surface = surface, design = f.cell, materials = true,
    position = rig.offset(rig.region(FAR_REGION), 10.5, 10.5) })
  check.eq("feedback single stamp out of reach refused", stamped, nil)
  check.eq("feedback single stamp out of reach says why", refusal, "no-network")
end

local function settled(surface)
  local f = storage.feedback
  check.truthy("feedback incomplete copy is drawn", count(rig.drawn(surface, marks_box(20))) > 0)
  local i = rig.call("get_project", f.incomplete)
  check.eq("feedback incomplete history", kinds(i), "started,incomplete,finished")
  local w = rig.call("get_project", f.waiting)
  check.eq("feedback paused and resumed history", kinds(w), "started,waiting,paused,resumed")
  local water = rig.call("get_project", f.water)
  check.eq("feedback water project finishes", water and water.status.level, "finished")
  check.eq("feedback water project history", kinds(water), "started,blocked,finished")
  local blocked = entry_of(water, "blocked")
  check.eq("feedback water blocks merged", blocked and blocked.reason, "water")
  check.truthy("feedback water blocks counted", blocked and blocked.count >= 2, blocked and blocked.count)
  check.eq("feedback finish counts copies", entry_of(water, "finished") and entry_of(water, "finished").copies, 4)
end

-- STALL_TICKS after its stamp the never-built copy is stalled; then both
-- projects stop and every mark goes.
local function stalled_then_stopped(surface)
  local f = storage.feedback
  local b = rig.call("get_project", f.building)
  check.eq("feedback stalled level", b and b.status.level, "stalled")
  check.eq("feedback stalled reason", b and b.status.reason, "missing-materials")
  check.eq("feedback stalled history", kinds(b), "started,stalled")
  rig.call("stop_project", f.building)
  rig.call("stop_project", f.incomplete)
  rig.call("stop_project", f.next)
  check.eq("feedback stopped project's next marks go", count(rig.drawn(surface, ahead_box())), 0)
  check.eq("feedback stopped building copy leaves no marks", count(rig.drawn(surface, marks_box(0))), 0)
  check.eq("feedback stopped incomplete copy leaves no marks", count(rig.drawn(surface, marks_box(20))), 0)
end

case.checks = { [300] = early, [1500] = settled, [11400] = stalled_then_stopped }

return case
