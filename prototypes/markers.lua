-- Socket and entry (plug) arrows, ore sensors and probes, drawn into
-- designs, and the internal anchor.
--
-- They are constant combinators underneath: a combinator's description and
-- signals live in the entity itself, so every blueprint, book, library edit
-- and copy-paste carries a socket's target natively, with no blueprint
-- arming through events (ADR-0001). An empty collision mask lets a marker sit
-- on top of the design's own entities. Their ghosts are destroyed the tick a
-- stamp creates them, so their items exist only in the cursor.

local GRAPHICS = require("scripts.const").GRAPHICS
local BASE = data.raw["constant-combinator"]["constant-combinator"]

local function four_way(image)
  local function facing(dir)
    return { filename = GRAPHICS .. image .. "-" .. dir .. ".png", size = 64, scale = 0.5 }
  end
  return { north = facing("north"), east = facing("east"), south = facing("south"), west = facing("west") }
end

local function marker(name, image)
  local m = table.deepcopy(BASE)
  m.name = name
  m.icons = nil
  m.icon = GRAPHICS .. image .. ".png"
  m.icon_size = 64
  m.minable = { mining_time = 0.1 }
  m.placeable_by = { item = name, count = 1 }
  m.collision_mask = { layers = {} }
  -- A point, not a box: a marker is a note in a design, not a building, so
  -- mods that judge ground by what a building's box covers leave it alone.
  -- tile_width and tile_height keep it snapping to tile centres.
  m.collision_box = { { 0, 0 }, { 0, 0 } }
  m.tile_width, m.tile_height = 1, 1
  m.selection_box = { { -0.5, -0.5 }, { 0.5, 0.5 } }
  m.selection_priority = 60
  m.flags = { "placeable-player", "player-creation", "not-on-map", "not-upgradable", "not-in-kill-statistics", "not-flammable" }
  m.sprites = four_way(image)
  -- A deepcopy keeps the combinator's group, so a marker and a real
  -- combinator would fast-replace (destroy) each other (spike S2).
  m.fast_replaceable_group = nil
  m.next_upgrade = nil
  -- Markers carry no signals worth wiring; keep players from wiring them.
  m.circuit_wire_max_distance = 0
  m.corpse = nil
  m.dying_explosion = nil
  m.created_effect = nil
  m.hidden_in_factoriopedia = true
  return m
end

local function item(name, image, order)
  return {
    type = "item", name = name, icon = GRAPHICS .. image .. ".png", icon_size = 64,
    flags = { "only-in-cursor", "spawnable" }, hidden = true,
    subgroup = "tool", order = "z[self-expanding-blueprints]-" .. order,
    stack_size = 50, place_result = name,
  }
end

-- A blueprint only accepts entities some item places, so the anchor has a
-- hidden item too; nobody ever holds it.
local anchor = marker("seb-anchor", "anchor")
anchor.hidden = true
anchor.sprites = { filename = GRAPHICS .. "anchor.png", size = 64, scale = 0.25 }

-- A sensor watches a square and a probe a tile, not a way: they look the
-- same facing anywhere.
local function still(name, image)
  local m = marker(name, image)
  m.sprites = { filename = GRAPHICS .. image .. ".png", size = 64, scale = 0.5 }
  return m
end
local sensor = still("seb-sensor", "sensor")
local probe = still("seb-probe", "probe")
local port = still("seb-port", "port")
local clear = still("seb-keep-clear", "clear")
-- The dashed frame around the design in hand while growing: each piece
-- draws a dash on its tile's outer edge. A blueprint preview tints all it
-- holds green, or red where blocked, and draws no range overlays, so the
-- dashes are the frame's only look. Its paste never happens (grow_cursor.lua).
local frame = marker("seb-grow-frame", "frame")
frame.hidden = true
frame.selection_box = nil

data:extend({
  marker("seb-socket", "socket"),
  marker("seb-entry", "entry"),
  sensor,
  probe,
  port,
  clear,
  frame,
  anchor,
  item("seb-socket", "socket", "b[socket]"),
  item("seb-entry", "entry", "c[entry]"),
  item("seb-sensor", "sensor", "c[sensor]"),
  item("seb-probe", "probe", "c[probe]"),
  item("seb-port", "port", "c[port]"),
  item("seb-keep-clear", "clear", "c[clear]"),
  item("seb-anchor", "anchor", "d[anchor]"),
  item("seb-grow-frame", "frame", "e[frame]"),
})
