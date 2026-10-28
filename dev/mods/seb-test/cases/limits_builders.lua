-- limits_builders.lua: blueprint builders under the limits (regions 80-89).
-- Written by the griefing-mitigation work; see DESIGN.md D43-D45.
--   merge:   a Find still running when its force is merged away ends; the
--            builder carries on as the other force's (here past its limit)
--   far:     a Stamp far from any generated land makes no map: ERR uncharted
--   charted: with builders_charted_only, generated but uncharted land is
--            refused: ERR uncharted
--   slow:    a 4 x 4 grid on a tiny share of server time goes down over
--            many reads, then answers DONE once built
--   room:    with building = 2 a 2 x 2 grid places two copies, waits, then
--            finishes; a second grid has its room back
--   leak:    a Stamp stopped, a builder removed, a surface deleted: each
--            gives its copies in flight back
--   cap:     builders = 1: a second builder shows the limit error and takes
--            over when the first goes; the limit raised lets a third in,
--            lowered sends one back to wait
--   sense:   Sense over 256 x 256 tiles gives what one search over it counts
--   capture: a friend's chest in the area stays out of the design

local check = require("lib.check")
local rig = require("lib.rig")
local builders = require("lib.builders")

local case = { name = "limits_builders" }

-- 80 and 84 are regressions.lua's; the leak site shares the far one's region.
local MERGE, FAR, CHARTED, SLOW, ROOM, CAP, SENSE, CAPTURE = 81, 82, 83, 85, 87, 88, 86, 89
local CELL = { rig.panel(1.5, 1.5) }
-- Never fits on bare floor: its drill has no ore to stand on.
local DRILL = { { name = "electric-mining-drill", position = { x = 1.5, y = 1.5 } } }
local FAR_AT = { x = 300000, y = 300000 }
local AT = { -10.5, 0 }
local VOID = "seb-lb-void"

local function lb()
  return storage.limits_builders
end

-- Floor around `o`, a force of the case's own with these limits, a builder
-- of it, and its design.
local function site(surface, o, name, limits, entities)
  rig.floor(surface, rig.box(o, -60, -60, 60, 60))
  local force = rig.own_force(name)
  if limits then rig.call("set_limits", force, limits) end
  local builder, program = builders.place(surface, rig.offset(o, AT[1], AT[2]), force)
  local design = entities and rig.call("register_design", force, rig.blueprint(entities, { label = name }))
  return { origin = o, force = force, builder = builder, program = program, design = design }
end

-- One more builder of a site's force, `dy` tiles below its first.
local function another(surface, s, dy)
  return builders.place(surface, rig.offset(s.origin, AT[1], AT[2] + dy), s.force)
end

local function output(name)
  return builders.output(lb()[name].builder)
end

-- Copies of the cell placed in a box: ghosts and built panels.
local function placed(surface, box)
  return rig.ghosts(surface, box) + rig.count(surface, box, "solar-panel")
end

-- The Sense site: entities, resources and trees across chunk edges and the
-- rectangle's own edges, and a builder per category outside it.
local SENSE_CATEGORIES = { "seb-sense-entities", "seb-sense-resources", "seb-sense-trees" }

local function sense_world(surface, box, force)
  for i, x in ipairs({ box.left + 4, box.left + 36, box.left + 100 }) do      -- chunk edges (box.left = 700)
    for j, y in ipairs({ box.top + 4, box.top + 68, box.top + 196 }) do
      surface.create_entity { name = (i + j) % 2 == 0 and "solar-panel" or "assembling-machine-1", position = { x + 0.5, y + 0.5 }, force = force }
      surface.create_entity { name = "iron-chest", position = { x + 5.5, y + 0.5 }, force = force }
      surface.create_entity { name = "iron-ore", position = { x + 8.5, y + 0.5 }, amount = 100 * i + j }
      surface.create_entity { name = "tree-01", position = { x - 0.1, y + 8.2 } }
    end
  end
  -- Across the rectangle's own edges, centres outside it.
  surface.create_entity { name = "solar-panel", position = { box.left - 0.5, box.top + 50.5 }, force = force }
  surface.create_entity { name = "solar-panel", position = { box.right + 0.5, box.top + 90.5 }, force = force }
  surface.create_entity { name = "crude-oil", position = { box.left + 36.5, box.top + 120.5 }, amount = 300000 }
  surface.create_entity { name = "tree-01", position = { box.left - 0.2, box.top + 10.5 } }
end

local function sense_setup(surface)
  local o = rig.region(SENSE)
  local box = rig.box(o, -100, -100, 156, 156)
  rig.floor(surface, rig.box(o, -110, -110, 166, 166))
  local force = rig.own_force("seb-lb-sense")
  sense_world(surface, box, force)
  local list = {}
  for i, name in ipairs(SENSE_CATEGORIES) do
    local builder, program = builders.place(surface, rig.offset(o, -106.5, -100 + i * 6), force)
    list[i] = { builder = builder, program = program, category = name }
  end
  return { box = box, force = force, builders = list }
end

local function capture_setup(surface)
  local c = site(surface, rig.region(CAPTURE), "seb-lb-capture")
  local own, friend = game.forces[c.force], game.forces[rig.own_force("seb-lb-capture-friend")]
  own.set_friend(friend, true)
  friend.set_friend(own, true)
  surface.create_entity { name = "iron-chest", position = rig.offset(c.origin, 10.5, 0.5), force = own }
  surface.create_entity { name = "wooden-chest", position = rig.offset(c.origin, 12.5, 0.5), force = friend }
  return c
end

-- Two builders on nauvis, one on a surface of its own, no robots anywhere:
-- every copy stays in flight until its request lets it go.
local function leak_setup(surface)
  local l = site(surface, rig.offset(rig.region(FAR), 150, 0), "seb-lb-leak", { building = 1 }, CELL)
  l.second, l.second_program = another(surface, l, 6)
  local void = game.create_surface(VOID)
  rig.floor(void, rig.box({ x = 0, y = 0 }, -40, -40, 40, 40))
  l.void, l.void_program = builders.place(void, { x = -10.5, y = 0 }, l.force)
  return l
end

function case.setup(surface)
  local s = { far = site(surface, rig.region(FAR), "seb-lb-far", { builders_charted_only = false }, CELL) }
  storage.limits_builders = s
  s.merge = site(surface, rig.region(MERGE), "seb-lb-merge-from", nil, DRILL)
  rig.own_force("seb-lb-merge-into")
  rig.call("set_limits", "seb-lb-merge-into", { builders = 1 })
  builders.place(surface, rig.offset(s.merge.origin, AT[1], AT[2] + 6), "seb-lb-merge-into")
  s.charted = site(surface, rig.region(CHARTED), "seb-lb-charted", { builders_charted_only = true }, CELL)
  -- Its share is set once its design is registered: registering is charged
  -- too (its lab chunks), and this site is about the grid's own pace (some
  -- 2,000 ticks): a worm next to it (seed 1) must leave its roboport be.
  s.slow = site(surface, rig.region(SLOW), "seb-lb-slow", nil, CELL)
  game.forces.enemy.set_cease_fire(s.slow.force, true)
  rig.call("set_limits", s.slow.force, { work = 1 })
  rig.network(surface, rig.offset(s.slow.origin, -25, -25), nil, s.slow.force)
  s.room = site(surface, rig.region(ROOM), "seb-lb-room", { building = 2 }, CELL)
  rig.network(surface, rig.offset(s.room.origin, -25, -25), nil, s.room.force)
  s.cap = site(surface, rig.region(CAP), "seb-lb-cap", { builders = 1 })
  s.cap.second, s.cap.second_program = another(surface, s.cap, 6)
  s.cap.third, s.cap.third_program = another(surface, s.cap, 12)
  s.leak, s.sense, s.capture = leak_setup(surface), sense_setup(surface), capture_setup(surface)
end

local SENSE_SMALL = { ["seb-sense"] = 1, ["seb-sense-entities"] = 1, ["signal-X"] = 0, ["signal-Y"] = 0, ["signal-W"] = 4, ["signal-H"] = 4 }

function case.start()
  local s = lb()
  builders.send(s.merge.program, { ["seb-find"] = 1, ["seb-design"] = s.merge.design, ["seb-radius"] = 64 })
  builders.send(s.far.program, { ["seb-stamp"] = 1, ["seb-design"] = s.far.design, ["signal-X"] = FAR_AT.x,
    ["signal-Y"] = FAR_AT.y, ["seb-absolute"] = 1 })
  builders.send(s.charted.program, { ["seb-stamp"] = 1, ["seb-design"] = s.charted.design, ["signal-X"] = 10, ["signal-Y"] = -1 })
  builders.send(s.slow.program, builders.grid(1, s.slow.design, 10, -1, 4))
  builders.send(s.room.program, builders.grid(1, s.room.design, 25, 15, 2))
  builders.send(s.leak.program, builders.grid(1, s.leak.design, 10, -1, 2))
  for _, program in ipairs({ s.cap.program, s.cap.second_program, s.cap.third_program }) do builders.send(program, SENSE_SMALL) end
  local box = s.sense.box
  for _, entry in ipairs(s.sense.builders) do
    builders.send(entry.program, { ["seb-sense"] = 1, [entry.category] = 1, ["signal-X"] = box.left, ["signal-Y"] = box.top,
      ["signal-W"] = 256, ["signal-H"] = 256, ["seb-absolute"] = 1 })
  end
  builders.send(s.capture.program, { ["seb-capture"] = 1, ["signal-X"] = 20, ["signal-Y"] = -1, ["signal-W"] = 6, ["signal-H"] = 3 })
end

local function merge_running()
  local find = output("merge")
  check.truthy("limits_builders a Find with a design that fits nowhere is still running", find["virtual/seb-ack"] == 1
    and not (find["virtual/seb-done"] or find["virtual/seb-error"]), check.show(find))
  game.merge_forces(lb().merge.force, "seb-lb-merge-into")
end

local function stamps_refused()
  check.truthy("limits_builders a Stamp far off the map answers uncharted", builders.failed(output("far"), 1, "uncharted"),
    check.show(output("far")))
  check.truthy("limits_builders a Stamp on uncharted land answers uncharted when builders keep to charted land",
    builders.failed(output("charted"), 1, "uncharted"), check.show(output("charted")))
end

local function grids_held(surface)
  local s = lb()
  local slow = placed(surface, rig.box(s.slow.origin, -3, -3, 17, 17))
  check.truthy("limits_builders a grid on a tiny share of server time goes down a few copies at a time", slow > 0 and slow < 16, slow)
  check.eq("limits_builders a grid stops at the team's copies in flight", placed(surface, rig.box(s.room.origin, 10, 10, 30, 30)), 2)
  check.eq("limits_builders ... also with no robots", placed(surface, rig.box(s.leak.origin, -3, -3, 30, 30)), 1)
  builders.send(s.leak.program, { ["seb-stop"] = 1 })
end

local function waiting(builder)
  local out = builders.output(builder)
  return out["virtual/seb-error-limit"] == 1 and out["virtual/seb-ack"] == nil, out
end

local function cap_held()
  local c = lb().cap
  check.eq("limits_builders the first builder works", output("cap")["virtual/seb-done"], 1)
  local held, out = waiting(c.second)
  check.truthy("limits_builders a builder past the team's limit shows the limit error and takes no request", held, check.show(out))
  c.builder.destroy()
end

-- Each step of the leak site frees the one copy in flight the next needs.
local LEAK = {
  [180] = function(l)
    check.truthy("limits_builders a stopped Stamp answers stopped", builders.failed(output("leak"), 1, "stopped"), check.show(output("leak")))
    builders.send(l.program, builders.grid(2, l.design, 10, 12, 1))
  end,
  [240] = function(l, surface)
    check.eq("limits_builders a stopped Stamp gives its copies in flight back", placed(surface, rig.box(l.origin, -3, -3, 30, 30)), 2)
    l.builder.destroy()
    builders.send(l.void_program, builders.grid(3, l.design, 10, 0, 1))
  end,
  [300] = function()
    check.eq("limits_builders a builder that goes gives its copies in flight back",
      placed(game.surfaces[VOID], rig.box({ x = 0, y = 0 }, -3, -6, 20, 10)), 1)
    game.delete_surface(VOID)
  end,
  [360] = function(l)
    builders.send(l.second_program, builders.grid(4, l.design, 10, 18, 1))
  end,
  [420] = function(l, surface)
    check.eq("limits_builders a builder on a deleted surface gives its copies in flight back",
      placed(surface, rig.box(l.origin, -3, -3, 30, 30)), 3)
  end,
}

local function took_over()
  local c = lb().cap
  local second = builders.output(c.second)
  check.truthy("limits_builders the waiting builder takes over when the first goes",
    second["virtual/seb-done"] == 1 and second["virtual/seb-error-limit"] == nil, check.show(second))
  check.truthy("limits_builders ... and only one", (waiting(c.third)), check.show(builders.output(c.third)))
  rig.call("set_limits", c.force, { builders = 2 })
  local merged = output("merge")
  check.truthy("limits_builders the merged builder's Find ended, and it waits under the other force's limit",
    merged["virtual/seb-ack"] == nil and merged["virtual/seb-error-limit"] == 1, check.show(merged))
end

local function sensed(surface)
  local s = lb().sense
  local area = { { s.box.left, s.box.top }, { s.box.right, s.box.bottom } }
  for _, entry in ipairs(s.builders) do
    local want, got = {}, builders.output(entry.builder)
    builders.COUNT[entry.category](surface, area, s.force, want)
    check.eq("limits_builders Sense " .. entry.category .. " over 256 x 256 done", got["virtual/seb-done"], 1)
    got["virtual/seb-ack"], got["virtual/seb-done"] = nil, nil
    check.same("limits_builders Sense " .. entry.category .. " over 256 x 256 counts what one search does", got, want)
  end
end

local function captured_and_raised()
  local c = lb().capture
  local out = output("capture")
  check.eq("limits_builders capture done", out["virtual/seb-done"], 1)
  local id = out["virtual/seb-design"]
  check.same("limits_builders a capture keeps only the team's own buildings", id and builders.design_entities(c.force, id), { "iron-chest" })
  local cap = lb().cap
  check.eq("limits_builders a raised limit lets a waiting builder in", builders.output(cap.third)["virtual/seb-done"], 1)
  rig.call("set_limits", cap.force, { builders = 1 })
end

local function lowered()
  local cap = lb().cap
  local second, third = waiting(cap.second), waiting(cap.third)
  check.truthy("limits_builders a lowered limit sends one builder back to wait", second ~= third,
    check.show({ builders.output(cap.second), builders.output(cap.third) }))
end

local function room_again()
  local s = lb()
  local out = output("room")
  check.truthy("limits_builders the held grid finishes", out["virtual/seb-done"] == 1 and out["virtual/seb-built"] == 4, check.show(out))
  builders.send(s.room.program, builders.grid(2, s.room.design, 5, 15, 2))
end

local function room_back(surface)
  check.eq("limits_builders a finished grid gives its room back", placed(surface, rig.box(lb().room.origin, -9, 10, 5, 30)), 2)
end

local function ended(surface)
  local slow, room = output("slow"), output("room")
  check.truthy("limits_builders the slow grid answers done once built", slow["virtual/seb-done"] == 1 and slow["virtual/seb-built"] == 16,
    check.show(slow))
  check.truthy("limits_builders the second grid finishes too", room["virtual/seb-done"] == 2 and room["virtual/seb-built"] == 4,
    check.show(room))
  local chunk = { x = math.floor(FAR_AT.x / 32), y = math.floor(FAR_AT.y / 32) }
  check.eq("limits_builders the far Stamp made no map", surface.is_chunk_generated(chunk), false)
end

case.checks = {
  [120] = function(surface) merge_running() stamps_refused() grids_held(surface) cap_held() end, [240] = took_over, [300] = sensed, [360] = captured_and_raised, [480] = lowered,
  [1800] = room_again, [1860] = room_back, [4800] = ended,
}
for tick, step in pairs(LEAK) do
  local before = case.checks[tick]
  case.checks[tick] = function(surface)
    if before then before(surface) end
    step(lb().leak, surface)
  end
end

return case
