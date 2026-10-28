-- circuit.lua: the blueprint builder, driven by a constant combinator wired
-- to its input, read from its output.
--   handshake: a request (verb = number) is acknowledged with ACK = number,
--              finished with DONE = number, refused with ERR = number and a
--              named error; one request at a time
--   verbs:     Stamp (DONE with the instance once built), Sense (counts),
--              Remove (exactly that copy goes), Grow (a project, its status
--              on the output, DONE when it finishes), Clear (an area)

local check = require("lib.check")
local rig = require("lib.rig")
local builders = require("lib.builders")

local case = { name = "circuit" }

local REGION = 37
local CELL = { rig.panel(1.5, 1.5) }
local PORT = {
  { name = "constant-combinator", position = { x = 0.5, y = 0.5 } }, { name = "seb-port", position = { x = 0.5, y = 0.5 } },
}

local function request(fields, items)
  builders.send(storage.circuit.combinator, fields, items)
end

local function output()
  return builders.output(storage.circuit.builder)
end

function case.setup(surface)
  local o = rig.site(surface, REGION)
  local builder, combinator = builders.place(surface, rig.offset(o, -10.5, 0))
  storage.circuit = {
    builder = builder, combinator = combinator, design = rig.design(CELL, "Circuit cell"), port = rig.design(PORT, "Circuit port"),
  }
  -- A yellow belt to upgrade, and the fast belts robots upgrade it with.
  surface.create_entity { name = "transport-belt", position = rig.offset(o, -20.5, 10.5), force = rig.FORCE }
  local chest = surface.find_entities_filtered { area = { { o.x - 40, o.y - 40 }, { o.x, o.y } }, name = "storage-chest" }[1]
  chest.insert { name = "fast-transport-belt", count = 10 }
end

local function stamp_request()
  local c = storage.circuit
  request({ ["seb-stamp"] = 1, ["seb-design"] = c.design, ["signal-X"] = 10, ["signal-Y"] = -1 })
end

local function acked()
  local out = output()
  check.eq("circuit stamp acknowledged", out["virtual/seb-ack"], 1)
  check.eq("circuit stamp not done before robots built it", out["virtual/seb-done"], nil)
  check.truthy("circuit stamp shows ghosts left while building", (out["virtual/seb-ghosts-left"] or 0) > 0, check.show(out))
end

local function stamp_done()
  local out = output()
  check.eq("circuit stamp done", out["virtual/seb-done"], 1)
  storage.circuit.instance = out["virtual/seb-instance"]
  check.truthy("circuit stamp names its instance", storage.circuit.instance)
  local inst = storage.circuit.instance and rig.call("get_instance", storage.circuit.instance)
  check.eq("circuit stamped copy complete", inst and inst.state, "complete")
  request({ ["seb-sense"] = 2, ["seb-sense-entities"] = 1, ["signal-X"] = 8, ["signal-Y"] = -4, ["signal-W"] = 8, ["signal-H"] = 8 })
end

local function sensed()
  local out = output()
  check.eq("circuit sense done", out["virtual/seb-done"], 2)
  check.eq("circuit sense counts the panel", out["item/solar-panel"], 1)
  request({ ["seb-remove"] = 3, ["seb-instance"] = storage.circuit.instance })
end

local function removed(surface)
  local out = output()
  check.eq("circuit remove done", out["virtual/seb-done"], 3)
  check.eq("circuit removed copy is gone", rig.call("get_instance", storage.circuit.instance), nil)
  request({ ["seb-stamp"] = 4, ["seb-design"] = 999999 })
end

local function refused()
  local out = output()
  check.eq("circuit refusal names the request", out["virtual/seb-error"], 4)
  check.eq("circuit refusal names the error", out["virtual/seb-error-unknown-design"], 1)
  local c = storage.circuit
  request({ ["seb-grow"] = 5, ["seb-design"] = c.design, ["signal-X"] = 10, ["signal-Y"] = 10, ["seb-count"] = 3,
    ["seb-grow-east"] = 1 })
end

local function growing()
  local out = output()
  check.eq("circuit grow acknowledged", out["virtual/seb-ack"], 5)
  -- Zero values are simply absent from a circuit network.
  check.eq("circuit grow shows the next copy's materials", out["item/solar-panel"], 1)
  check.truthy("circuit grow shows ghosts left", (out["virtual/seb-ghosts-left"] or 0) > 0, check.show(out))
end

local function grown()
  local out = output()
  check.eq("circuit grow done", out["virtual/seb-done"], 5)
  check.eq("circuit grow built three", out["virtual/seb-built"], 3)
  request({ ["seb-clear"] = 6, ["signal-X"] = 8, ["signal-Y"] = 8, ["signal-W"] = 14, ["signal-H"] = 6 })
end

local function cleared(surface)
  local out = output()
  check.eq("circuit clear done", out["virtual/seb-done"], 6)
  local o = rig.region(REGION)
  check.eq("circuit clear removed the panels", rig.count(surface, rig.box(o, -3, 7, 12, 15), "solar-panel"), 0)
  local c = storage.circuit
  request({ ["seb-stamp"] = 7, ["seb-design"] = c.design, ["signal-X"] = 10, ["signal-Y"] = 20, ["seb-grid-x"] = 2, ["seb-grid-y"] = 2,
    ["seb-spacing"] = 1 })
end

local function gridded()
  local out = output()
  check.eq("circuit grid stamp done", out["virtual/seb-done"], 7)
  check.eq("circuit grid stamped four", out["virtual/seb-built"], 4)
  request({ ["seb-capture"] = 8, ["signal-X"] = 7, ["signal-Y"] = 17, ["signal-W"] = 10, ["signal-H"] = 10 })
end

local function captured()
  local out = output()
  check.eq("circuit capture done", out["virtual/seb-done"], 8)
  local id = out["virtual/seb-design"]
  local found
  for _, row in ipairs(rig.call("list_designs", rig.FORCE)) do
    if row.id == id then found = row end
  end
  check.truthy("circuit capture made a design", found and found.name:find("Captured"), found and found.name)
  request({ ["seb-find"] = 9, ["seb-design"] = storage.circuit.design, ["signal-X"] = 11, ["signal-Y"] = 21, ["seb-radius"] = 12 })
end

local function found_spot()
  local out = output()
  check.eq("circuit find done", out["virtual/seb-done"], 9)
  check.truthy("circuit find gives a spot", out["virtual/signal-X"] ~= nil or out["virtual/signal-Y"] ~= nil, check.show(out))
  request({ ["seb-upgrade"] = 10, ["signal-X"] = -10, ["signal-Y"] = 10, ["signal-W"] = 1, ["signal-H"] = 1 })
end

local function upgraded(surface)
  local out = output()
  check.eq("circuit upgrade done", out["virtual/seb-done"], 10)
  check.eq("circuit upgrade made it fast", rig.count(surface, rig.box(rig.region(REGION), -21, 10, -20, 11), "fast-transport-belt"), 1)
  local c = storage.circuit
  c.port_copy = rig.call("stamp", { force = rig.FORCE, surface = surface, design = c.port, position = rig.offset(rig.region(REGION), -15.5, 15.5) })
  check.truthy("circuit port copy stamped", c.port_copy)
end

local function port_written()
  local c = storage.circuit
  local inst = rig.call("get_instance", c.port_copy)
  check.eq("circuit port copy built", inst and inst.state, "complete")
  request({ ["seb-write"] = 11, ["seb-instance"] = c.port_copy }, { ["iron-plate"] = 7 })
end

local function port_read()
  local out = output()
  check.eq("circuit write done", out["virtual/seb-done"], 11)
  request({ ["seb-read"] = 12, ["seb-instance"] = storage.circuit.port_copy })
end

local function port_checked()
  local out = output()
  check.eq("circuit read done", out["virtual/seb-done"], 12)
  check.eq("circuit read gives what was written", out["item/iron-plate"], 7)
end

case.start = stamp_request
case.checks = {
  [120] = acked, [1200] = stamp_done, [1260] = sensed, [2400] = removed, [2460] = refused,
  [2520] = growing, [4800] = grown, [6600] = cleared, [8400] = gridded, [8460] = captured, [8700] = found_spot,
  [9600] = upgraded, [10500] = port_written, [10560] = port_read, [10620] = port_checked,
}

return case
