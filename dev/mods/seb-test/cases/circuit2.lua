-- circuit2.lua: builders given odd requests, and builders that live odd lives.
--   range:     X, Y or Spacing far off the map is refused (ERR invalid)
--              instead of an engine error on every load
--   stop:      Stop ends a stamp that waits for robots that never come
--              (ERR stopped), and the next request is served
--   stall:     left alone, such a stamp ends once its copy stalls, with
--              ERR out of range
--   handshake: a program that sends its next request as soon as one is
--              accepted still sees DONE first, with the copy number
--   inside:    a copy whose design holds a builder retires once removed,
--              and updates in place
--   clear:     a Clear whose orders someone cancels ends
--   output:    a builder cloned with its area gets one output, not two; one
--              whose output is destroyed gets a new one and answers

local check = require("lib.check")
local rig = require("lib.rig")
local builders = require("lib.builders")

local case = { name = "circuit2" }

local DRIVEN, INSIDE, CLEAR, OUTPUT = 53, 54, 55, 56
local STOCK = { { "seb-builder", 10 }, { "solar-panel", 40 }, { "iron-chest", 10 } }
local BUILDER_AT = { -10.5, 0 }
-- From the builder, a tile past the reach of the roboport at -25, -25.
local FAR_X, FAR_Y = 56, 45
local STOP_AFTER = 120

local CELL = { rig.panel(1.5, 1.5) }
local LONE = { { name = "seb-builder", position = { x = 0.5, y = 1 } } }
local CELL_V1 = { { name = "seb-builder", position = { x = 0.5, y = 1 } }, rig.panel(2.5, 1.5) }
local CELL_V2 = { { name = "seb-builder", position = { x = 0.5, y = 1 } }, rig.panel(2.5, 1.5), rig.panel(5.5, 1.5) }

-- The program: each request goes on the wire once the one before is
-- answered. Request numbers are the step numbers. on_ack "stop" puts Stop
-- on the wire a while after the request is accepted; "next" sends the next
-- request at once, as a program that only waits for ACK does.
local function program(design)
  return {
    { fields = { ["seb-stamp"] = 1, ["seb-design"] = design, ["signal-X"] = 10000000 } },
    { fields = { ["seb-sense"] = 2, ["seb-sense-entities"] = 1, ["signal-X"] = 2147483647 } },
    { fields = { ["seb-stamp"] = 3, ["seb-design"] = design, ["seb-grid-x"] = 2, ["seb-spacing"] = 100000 } },
    { fields = { ["seb-stamp"] = 4, ["seb-design"] = design, ["signal-X"] = FAR_X, ["signal-Y"] = FAR_Y }, on_ack = "stop" },
    { fields = { ["seb-sense"] = 5, ["seb-sense-entities"] = 1 } },
    { fields = { ["seb-stamp"] = 6, ["seb-design"] = design, ["signal-X"] = 10, ["signal-Y"] = -1 }, on_ack = "next" },
    { fields = { ["seb-sense"] = 7, ["seb-sense-entities"] = 1, ["signal-X"] = 8, ["signal-Y"] = -4, ["signal-W"] = 8, ["signal-H"] = 8 } },
  }
end

local function send_step(d, i)
  local step = d.steps[i]
  if step and not step.sent then
    builders.send(d.combinator, step.fields)
    step.sent = true
  end
end

local function on_ack(d, step, tick)
  d.acked_at[d.step] = d.acked_at[d.step] or tick
  if step.on_ack == "next" then
    send_step(d, d.step + 1)
  elseif step.on_ack == "stop" and tick >= d.acked_at[d.step] + STOP_AFTER then
    builders.send(d.combinator, { ["seb-stop"] = 1 })
  end
end

-- Sampled more often than the builder answers, so every answer is seen.
local function drive(event)
  local d = storage.circuit2 and storage.circuit2.driven
  if not (d and d.step and d.builder.valid) then return end
  local out = builders.output(d.builder)
  local answered = out["virtual/seb-done"] or out["virtual/seb-error"]
  if answered and not d.answers[answered] then d.answers[answered] = out end
  local step = d.steps[d.step]
  if not step then return end
  if d.answers[d.step] then
    d.step = d.step + 1
    return send_step(d, d.step)
  end
  if step.on_ack and out["virtual/seb-ack"] == d.step then on_ack(d, step, event.tick) end
end
script.on_nth_tick(6, drive)

local function site(surface, region)
  local o = rig.region(region)
  rig.floor(surface, rig.box(o, -60, -60, 60, 60))
  rig.network(surface, rig.offset(o, -25, -25), STOCK)
  return o
end

local function output_count(surface, box)
  return surface.count_entities_filtered { area = { { box.left, box.top }, { box.right, box.bottom } }, name = "seb-builder-output" }
end

-- A builder cloned with its area, and one whose output is destroyed.
local function output_setup(surface)
  local o = site(surface, OUTPUT)
  local builder, combinator = builders.place(surface, rig.offset(o, BUILDER_AT[1], BUILDER_AT[2]))
  local source, destination = rig.box(o, -14, -2, -8, 3), rig.box(o, -14, 8, -8, 13)
  surface.clone_area {
    source_area = { { source.left, source.top }, { source.right, source.bottom } },
    destination_area = { { destination.left, destination.top }, { destination.right, destination.bottom } },
  }
  check.eq("circuit2 a cloned builder has one output", output_count(surface, destination), 1)
  for _, old in pairs(surface.find_entities_filtered { name = "seb-builder-output", position = builder.position, radius = 0.5 }) do
    old.destroy()
  end
  return { builder = builder, combinator = combinator, destination = destination }
end

function case.setup(surface)
  local o = site(surface, DRIVEN)
  local builder, combinator = builders.place(surface, rig.offset(o, BUILDER_AT[1], BUILDER_AT[2]))
  local cell = rig.design(CELL, "Circuit2 cell")
  site(surface, INSIDE)
  local c = site(surface, CLEAR)
  local clear_builder, clear_program = builders.place(surface, rig.offset(c, BUILDER_AT[1], BUILDER_AT[2]))
  local chest = surface.create_entity { name = "iron-chest", position = rig.offset(c, 45.5, 45.5), force = rig.FORCE }
  storage.circuit2 = {
    driven = { builder = builder, combinator = combinator, steps = program(cell), answers = {}, acked_at = {} },
    lone = rig.design(LONE, "Builder only"), cell = rig.design(CELL_V1, "Builder cell"),
    clear = { builder = clear_builder, combinator = clear_program, chest = chest },
    output = output_setup(surface),
  }
end

function case.start(surface)
  local c = storage.circuit2
  c.driven.step = 1
  send_step(c.driven, 1)
  local o = rig.region(INSIDE)
  c.lone_copy = rig.call("stamp", { force = rig.FORCE, surface = surface, design = c.lone, position = rig.offset(o, 0.5, 0.5) })
  c.cell_copy = rig.call("stamp", { force = rig.FORCE, surface = surface, design = c.cell, position = rig.offset(o, 0.5, 10.5) })
  check.truthy("circuit2 copies holding builders stamped", c.lone_copy and c.cell_copy)
  builders.send(c.clear.combinator, { ["seb-clear"] = 1, ["signal-X"] = FAR_X, ["signal-Y"] = FAR_Y })
  builders.send(c.output.combinator, { ["seb-sense"] = 1, ["seb-sense-entities"] = 1 })
end

local function clear_waits()
  local c = storage.circuit2.clear
  local out = builders.output(c.builder)
  check.eq("circuit2 clear accepted", out["virtual/seb-ack"], 1)
  check.eq("circuit2 clear waits for robots that never come", out["virtual/seb-done"], nil)
  check.truthy("circuit2 chest ordered out", c.chest.valid and c.chest.to_be_deconstructed())
  c.chest.cancel_deconstruction(rig.FORCE)
end

-- The stamp goes out early: its copy stalls STALL_TICKS (3 minutes) later.
local function healed()
  local c = storage.circuit2.output
  check.eq("circuit2 a builder whose output was destroyed still answers", builders.output(c.builder)["virtual/seb-done"], 1)
  builders.send(c.combinator, { ["seb-stamp"] = 2, ["seb-design"] = storage.circuit2.driven.steps[1].fields["seb-design"],
    ["signal-X"] = FAR_X, ["signal-Y"] = FAR_Y })
end

local function stalled()
  local out = builders.output(storage.circuit2.output.builder)
  check.eq("circuit2 a stamp no robots reach fails once its copy stalls", out["virtual/seb-error"], 2)
  check.eq("circuit2 ... as out of range", out["virtual/seb-error-out-of-range"], 1)
end

local function cancelled(surface)
  local c = storage.circuit2
  check.eq("circuit2 clear ends once its order is cancelled", builders.output(c.clear.builder)["virtual/seb-done"], 1)
  local box = c.output.destination
  for _, b in pairs(surface.find_entities_filtered { area = { { box.left, box.top }, { box.right, box.bottom } }, name = "seb-builder" }) do
    b.destroy()
  end
end

local function inside_built(surface)
  local c = storage.circuit2
  check.eq("circuit2 no output left behind by the cloned builder", output_count(surface, c.output.destination), 0)
  local lone = rig.call("get_instance", c.lone_copy)
  check.eq("circuit2 lone builder copy built", lone and lone.state, "complete")
  rig.call("remove_instance", c.lone_copy)
  local cell = rig.call("get_instance", c.cell_copy)
  check.eq("circuit2 builder cell built", cell and cell.state, "complete")
  local id = rig.call("register_design", rig.FORCE, rig.blueprint(CELL_V2, { label = "Builder cell" }))
  check.eq("circuit2 builder cell v2 is the next version", id, c.cell)
  local ok, why = rig.call("update_instance", c.cell_copy)
  check.eq("circuit2 a copy holding a builder updates in place", ok, true, why)
end

local function inside_done(surface)
  local c = storage.circuit2
  check.eq("circuit2 a removed copy holding a builder retires", rig.call("get_instance", c.lone_copy), nil)
  local cell = rig.call("get_instance", c.cell_copy)
  check.eq("circuit2 updated builder cell built", cell and cell.state, "complete")
  check.eq("circuit2 updated builder cell has both panels",
    rig.count(surface, rig.box(rig.region(INSIDE), -2, 8, 12, 16), "solar-panel"), 2)
end

local function program_ran()
  local a = storage.circuit2.driven.answers
  local function refused(n, name)
    local out = a[n] or {}
    return out["virtual/seb-error"] == n and out["virtual/seb-error-" .. name] == 1
  end
  check.truthy("circuit2 X far off the map refused", refused(1, "invalid"), check.show(a[1]))
  check.truthy("circuit2 sense far off the map refused", refused(2, "invalid"), check.show(a[2]))
  check.truthy("circuit2 huge spacing refused", refused(3, "invalid"), check.show(a[3]))
  check.truthy("circuit2 stop ends a stamp no robots reach", refused(4, "stopped"), check.show(a[4]))
  check.eq("circuit2 the request after a stop is served", a[5] and a[5]["virtual/seb-done"], 5)
  check.eq("circuit2 done shows before the next request is taken", a[6] and a[6]["virtual/seb-done"], 6)
  check.truthy("circuit2 done comes with the copy number", a[6] and a[6]["virtual/seb-instance"], check.show(a[6]))
  check.eq("circuit2 the request sent on ACK is served", a[7] and a[7]["virtual/seb-done"], 7)
end

case.checks = {
  [180] = healed, [600] = clear_waits, [900] = cancelled, [1200] = inside_built, [2400] = inside_done, [4200] = program_ran,
  [11340] = stalled,
}

return case
