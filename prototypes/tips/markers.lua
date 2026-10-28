-- Tips and Tricks entries about what a player draws into a design: sockets
-- and plugs (turning corners, naming another design), pools, probes, Keep
-- clear and ore sensors (and removing the copies that are mined out). Each
-- has one simulation that runs the mod itself (prototypes/tips/setup.lua says
-- how a scene is written; exhibit.lua adds what these scenes need to show a
-- build as the player draws it).

local setup = require("prototypes.tips.setup")
local exhibit = require("prototypes.tips.exhibit")

-- The robots' speed modifier (setup.WORLD sets 4): a copy is built about as
-- fast as it is read.
local ROBOT_SPEED = 10

local function simulation(seconds, scene)
  return setup.looping(seconds, scene, exhibit.TOOLS .. "force.worker_robots_speed_modifier = " .. ROBOT_SPEED .. "\n")
end

-- Every entry carries the icon of its marker as its tag, so a sub-entry's
-- icon sits one step right of its parent's and the list reads as a tree.
local function tip(name, order, indent, extra)
  local item = {
    type = "tips-and-tricks-item", name = name, category = "self-expanding-blueprints", order = order,
    indent = indent, starting_status = "unlocked", dependencies = { "seb-grow" },
  }
  for k, v in pairs(extra) do item[k] = v end
  return item
end

-- Sockets and plugs: each copy's plug lands on the last copy's socket, one
-- row lower, so the row steps down.
local SOCKETS = [=[
  -- The roboport is under the middle of the staircase (x -20 to 22, y -7 to 2),
  -- and the drawn build below its start.
  camera(0.75, 1, 1)
  network(1, 7, 30, { { "solar-panel", 20 } })
  local step = {
    { name = "solar-panel", position = { 1.5, 1.5 } }, { name = "solar-panel", position = { 4.5, 1.5 } },
    { name = "seb-entry", position = { 0.5, 0.5 }, direction = EAST },
    { name = "seb-socket", position = { 6.5, 1.5 }, direction = EAST },
  }
  exhibit(step, -20, 4)
  note({ "item-name.seb-entry" }, -20.3, 2.9)
  note({ "item-name.seb-socket" }, -12.2, 5.5)
  local id = design(step, "Step")
  at(1, function()
    pulse(-17, -5.5)
    grow { design = id, point = { -17, -5.5 }, max_instances = 7 }
  end)
]=]

-- A socket that points another way than the plug turns the next copy: four
-- quarter turns close a belt into a ring.
local TURN = [=[
  -- The ring takes 9 x 9 tiles (x -7 to 2, y -5 to 4); the drawn build is to its right.
  camera(-1.25, -1.75, 1.3)
  network(-12, 2, 30, { { "transport-belt", 40 } })
  local corner = {}
  for i = 0, 6 do corner[#corner + 1] = { name = "transport-belt", position = { i + 0.5, 0.5 }, direction = EAST } end
  corner[#corner + 1] = { name = "transport-belt", position = { 7.5, 0.5 }, direction = SOUTH }
  corner[#corner + 1] = { name = "seb-entry", position = { 0.5, 0.5 }, direction = EAST }
  corner[#corner + 1] = { name = "seb-socket", position = { 7.5, 1.5 }, direction = SOUTH }
  exhibit(corner, 6, -7)
  note({ "item-name.seb-entry" }, 5.7, -8.1)
  note({ "item-name.seb-socket" }, 14.5, -3.9, "right")
  local id = design(corner, "Belt corner")
  at(1, function()
    pulse(-2, -4.5)
    grow { design = id, point = { -2, -4.5 } }
  end)
  -- Plates on the finished ring, to show it runs.
  at(7, function()
    local belts = surface.find_entities_filtered { name = "transport-belt", area = { { -7, -5 }, { 2, 4 } } }
    local function before(a, b)
      return a.position.x < b.position.x or (a.position.x == b.position.x and a.position.y < b.position.y)
    end
    table.sort(belts, before)
    for i = 1, #belts, 3 do belts[i].get_transport_line(1).insert_at_back { name = "iron-plate", count = 1 } end
  end)
]=]

-- A socket that names another design: panels and accumulators take turns.
local NAMED = [=[
  -- The row (x -18 to 2, y -3 to 3) has the two designs drawn under it, each
  -- with what its socket's description says.
  camera(-3.5, 4, 1.4)
  network(8, 3, 30, { { "solar-panel", 10 }, { "accumulator", 14 } })
  local panels = {
    { name = "solar-panel", position = { 1.5, 1.5 } }, { name = "solar-panel", position = { 1.5, 4.5 } },
    { name = "seb-entry", position = { 0.5, 0.5 }, direction = EAST },
    { name = "seb-socket", position = { 3.5, 0.5 }, direction = EAST, player_description = "Accumulators" },
  }
  local accumulators = {
    { name = "accumulator", position = { 1, 1 } }, { name = "accumulator", position = { 1, 3 } },
    { name = "accumulator", position = { 1, 5 } },
    { name = "seb-entry", position = { 0.5, 0.5 }, direction = EAST },
    { name = "seb-socket", position = { 2.5, 0.5 }, direction = EAST, player_description = "Panels" },
  }
  exhibit(panels, -17.5, 4.5)
  note("Accumulators", -12.7, 5)
  exhibit(accumulators, -5, 4.5)
  note("Panels", -1.2, 5)
  design(accumulators, "Accumulators")
  local id = design(panels, "Panels")
  at(1, function()
    pulse(-16.5, 0)
    grow { design = id, point = { -16.5, 0 }, max_instances = 8 }
  end)
]=]

-- One field piece: w x h tiles of solar panels (3 x 3 each), a socket east
-- and one south, both naming the pool.
local FIELD_PIECE = [=[
  local function piece(w, h)
    local entities = {}
    for i = 0, w / 3 - 1 do
      for j = 0, h / 3 - 1 do
        entities[#entities + 1] = { name = "solar-panel", position = { 1.5 + 3 * i, 1.5 + 3 * j } }
      end
    end
    entities[#entities + 1] = { name = "seb-socket", position = { w + 0.5, h / 2 }, direction = EAST, player_description = "Solar field" }
    entities[#entities + 1] = { name = "seb-socket", position = { w / 2, h + 0.5 }, direction = SOUTH, player_description = "Solar field" }
    return entities
  end
]=]

-- A pool: one socket names a book, and the first piece that fits is built,
-- so smaller pieces finish the edges and the corner of a field by a lake.
-- Each finished piece gets an outline and its design's name, so the pieces
-- can be told apart.
local POOLS = FIELD_PIECE .. [=[
  -- The land is 21 x 21 tiles from (-12, -11): water on its east side and
  -- south, so growth ends in 2 x 2 blocks, a strip down the east, a slab along
  -- the south and a single in the corner.
  camera(-5, 0.5, 0.9)
  tiles("water", 9, -13, 13, 13)
  tiles("water", -14, 10, 9, 13)
  network(-18, 0, 40, { { "solar-panel", 60 } })
  local ids = book("Solar field", {
    { "Block", piece(9, 9) }, { "Strip", piece(3, 9) }, { "Slab", piece(9, 3) }, { "Single", piece(3, 3) },
  })
  local names = {}
  for i, label in ipairs { "Block", "Strip", "Slab", "Single" } do names[ids[i]] = label end
  script.on_event(remote.call(MOD, "get_event_id", "on_instance_completed"), function(event)
    local box = remote.call(MOD, "get_instance", event.instance_id).footprint
    rendering.draw_rectangle { surface = surface, filled = false, width = 2, color = { r = 0.7, g = 0.7, b = 0.7, a = 0.7 },
      left_top = { box.left + 0.15, box.top + 0.15 }, right_bottom = { box.right - 0.15, box.bottom - 0.15 } }
    rendering.draw_text { surface = surface, text = names[event.design_id], scale = 1.4, color = WHITE,
      target = { (box.left + box.right) / 2, (box.top + box.bottom) / 2 }, alignment = "center", vertical_alignment = "middle" }
  end)
  at(1, function()
    pulse(-7.5, -6.5)
    grow { design = ids[1], point = { -7.5, -6.5 } }
  end)
]=]

-- A solar panel with a column of Keep clear on its east edge: its copies
-- leave that lane empty, a tree in a lane is cleared and a chest in one
-- closes that copy's spot.
local CLEAR = [=[
  -- The field is 5 x 3 copies of 4 x 3 tiles from (-16, -5), each with its
  -- lane on its east tile; lane(column, row) is the middle of one, counting
  -- from 0. The chest's copy is in neither the first row nor the first column,
  -- so the copies after it are reached from their other side.
  camera(-11, 0.25, 1.3)
  network(-21, 5, 30, { { "solar-panel", 20 } })
  local area = { left = -16, top = -5, right = 4, bottom = 4 }
  local function lane(column, row)
    return { area.left + 4 * column + 3.5, area.top + 3 * row + 1.5 }
  end
  local build = { { name = "solar-panel", position = { 1.5, 1.5 } } }
  for y = 0.5, 2.5 do build[#build + 1] = { name = "seb-keep-clear", position = { 3.5, y } } end
  exhibit(build, -24, -6)
  note({ "item-name.seb-keep-clear" }, -22, -1.8, "center")
  local id = design(build, "Panel and lane")
  surface.create_entity { name = "tree-01", position = lane(1, 0) }
  surface.create_entity { name = "wooden-chest", position = lane(2, 1), force = force }
  local selection = drag(area, GREEN, 0.8)
  at(1, function()
    selection.destroy()
    grow { design = id, area = area }
  end)
]=]

-- A solar block with a deny probe on each corner: no ore under any corner.
-- The ore lies under two cells of a 5 x 3 field of such blocks.
local PROBES = [=[
  -- The field is 5 x 3 blocks of 6 x 6 tiles from (-15, -9); the ore lies under
  -- the blocks at row 1, column 1 and row 2, column 3 (counting from 0).
  camera(-5.5, 0, 1)
  network(-21, 6, 40, { { "solar-panel", 60 } })
  local function probe(x, y)
    return { name = "seb-probe", position = { x, y }, control_behavior = { sections = { sections = { { index = 1, filters = {
      { index = 1, type = "virtual", name = "signal-deny", quality = "normal", comparator = "=", count = 1 } } } } } } }
  end
  local block = {
    { name = "solar-panel", position = { 1.5, 1.5 } }, { name = "solar-panel", position = { 4.5, 1.5 } },
    { name = "solar-panel", position = { 1.5, 4.5 } }, { name = "solar-panel", position = { 4.5, 4.5 } },
    probe(0.5, 0.5), probe(5.5, 0.5), probe(0.5, 5.5), probe(5.5, 5.5),
  }
  exhibit(block, -24, -9)
  note({ "", { "item-name.seb-probe" }, ": ", { "virtual-signal-name.signal-deny" } }, -24.5, -1.9)
  local id = design(block, "Solar block")
  -- A patch fills a cell (cells are 6 x 6 tiles from (-15, -9)), edges ragged
  -- but the corners always covered: that is where the probes look.
  local function patch(left, top)
    for x = 0, 5 do
      for y = 0, 5 do
        local edge = x == 0 or x == 5 or y == 0 or y == 5
        local corner = (x == 0 or x == 5) and (y == 0 or y == 5)
        if corner or not edge or (3 * x + 5 * y) % 4 ~= 0 then
          surface.create_entity { name = "iron-ore", position = { left + x + 0.5, top + y + 0.5 }, amount = 400 }
        end
      end
    end
  end
  patch(-9, -3)
  patch(3, 3)
  local area = { left = -15, top = -9, right = 15, bottom = 9 }
  local selection = drag(area, GREEN, 0.8)
  at(1, function()
    selection.destroy()
    grow { design = id, area = area }
  end)
]=]

-- Drill outposts that come one after another as the ore under each runs out:
-- the sensor on the drill watches its mining area. COPIES and RETIRE are set
-- in front of the scene. The roboport stands below the view: robots fly in.
local OUTPOSTS = [=[
  local left, right = -2 * COPIES, 2 * COPIES
  camera(0, -2.5, 8 / COPIES)
  network(0, 14, 30, { { "electric-mining-drill", 10 }, { "wooden-chest", 10 } })
  -- A fixed line of poles below the row, seven tiles apart so that their
  -- supply areas meet: removing a copy never cuts the others off.
  for x = left + 3.5, right + 3.5, 7 do
    surface.create_entity { name = "medium-electric-pole", position = { x, 3.5 }, force = force }
  end
  -- One ore under the middle of each drill: a drill mines one in two seconds.
  for k = 0, COPIES - 1 do surface.create_entity { name = "iron-ore", position = { left + 1.5 + 4 * k, 0.5 }, amount = 1 } end
  local outpost = {
    { name = "electric-mining-drill", position = { 1.5, 1.5 }, direction = EAST },
    { name = "wooden-chest", position = { 3.5, 1.5 } },
    { name = "seb-sensor", position = { 1.5, 2.5 } },
    { name = "seb-socket", position = { 4.5, 1.5 }, direction = EAST },
  }
  exhibit(outpost, left, -8)
  note({ "item-name.seb-sensor" }, left - 0.5, -4)
  local id = design(outpost, "Outpost")
  local area = { left = left, top = -1, right = right, bottom = 2 }
  local selection = drag(area, GREEN, 0.8)
  at(1, function()
    selection.destroy()
    grow { design = id, area = area, max_instances = COPIES, retire_depleted = RETIRE }
  end)
]=]

local function outposts(copies, retire)
  return "local COPIES, RETIRE = " .. copies .. ", " .. tostring(retire) .. "\n" .. OUTPOSTS
end

return {
  tip("seb-sockets", "h", 1, { tag = "[img=item/seb-socket]", simulation = simulation(15, SOCKETS) }),
  tip("seb-sockets-turn", "i", 2, { tag = "[img=item/seb-socket]", simulation = simulation(12, TURN) }),
  tip("seb-sockets-named", "j", 2, { tag = "[img=item/seb-socket]", simulation = simulation(18, NAMED) }),
  tip("seb-pools", "k", 1, { tag = "[item=blueprint-book]", simulation = simulation(13, POOLS) }),
  tip("seb-probes", "l", 1, { tag = "[img=item/seb-probe]", simulation = simulation(19, PROBES) }),
  tip("seb-keep-clear", "l-clear", 1, { tag = "[img=item/seb-keep-clear]", simulation = simulation(17, CLEAR) }),
  tip("seb-mining", "m", 1, { tag = "[img=item/seb-sensor]", simulation = simulation(22, outposts(5, false)) }),
  tip("seb-mining-remove", "n", 2, { tag = "[img=item/seb-sensor]", simulation = simulation(31, outposts(6, true)) }),
}
