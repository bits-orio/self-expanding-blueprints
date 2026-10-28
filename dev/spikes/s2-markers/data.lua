-- S2 marker candidates.
--   seb-spike-socket         the candidate: a constant combinator copy with an empty collision mask
--   seb-spike-socket-nowire  same, with circuit_wire_max_distance = 0 (can wires be kept off it?)
--   seb-spike-socket-nofrg   same, without the inherited fast_replaceable_group
--   seb-spike-tagmarker      the fallback: a simple-entity-with-owner carrying blueprint entity tags
--   seb-spike-target         a virtual signal for the socket's target design number

local ARROWS = "__base__/graphics/icons/arrows/"
local CC_ICON = "__base__/graphics/icons/constant-combinator.png"

local function marker_item(name, icon)
  return {
    type = "item",
    name = name,
    icon = icon,
    icon_size = 64,
    subgroup = "other",
    order = "z[" .. name .. "]",
    stack_size = 50,
    flags = {"only-in-cursor", "spawnable"},
    hidden = true,
    place_result = name,
  }
end

local function socket_variant(name)
  local e = table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
  e.name = name
  e.collision_mask = {layers = {}}
  e.minable = {mining_time = 0.1}
  e.hidden = true
  return e
end

local socket = socket_variant("seb-spike-socket")

local nowire = socket_variant("seb-spike-socket-nowire")
nowire.circuit_wire_max_distance = 0
nowire.draw_circuit_wires = false
nowire.draw_copper_wires = false

local nofrg = socket_variant("seb-spike-socket-nofrg")
nofrg.fast_replaceable_group = nil

local function arrow(file)
  return {filename = ARROWS .. file, size = 64, scale = 0.5}
end

local tagmarker = {
  type = "simple-entity-with-owner",
  name = "seb-spike-tagmarker",
  icon = ARROWS .. "up-arrow.png",
  icon_size = 64,
  flags = {"placeable-neutral", "placeable-player", "player-creation", "not-on-map"},
  hidden = true,
  max_health = 1,
  minable = {mining_time = 0.1},
  collision_box = {{-0.35, -0.35}, {0.35, 0.35}},
  selection_box = {{-0.5, -0.5}, {0.5, 0.5}},
  collision_mask = {layers = {}},
  picture = {
    north = arrow("up-arrow.png"),
    east = arrow("right-arrow.png"),
    south = arrow("down-arrow.png"),
    west = arrow("left-arrow.png"),
  },
}

data:extend({
  socket,
  nowire,
  nofrg,
  tagmarker,
  marker_item("seb-spike-socket", CC_ICON),
  marker_item("seb-spike-socket-nowire", CC_ICON),
  marker_item("seb-spike-socket-nofrg", CC_ICON),
  marker_item("seb-spike-tagmarker", ARROWS .. "up-arrow.png"),
  {
    type = "virtual-signal",
    name = "seb-spike-target",
    icon = "__base__/graphics/icons/signal/signal_A.png",
    subgroup = "virtual-signal-letter",
    order = "z[seb-spike-target]",
  },
})
