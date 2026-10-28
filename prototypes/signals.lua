-- The circuit layer's virtual signals (DESIGN.md section 4): one named
-- signal per verb, option, answer and error, never a number with two
-- meanings. Icons are vanilla pictures with the mod's badge in a corner, so
-- they read as "this mod's" next to vanilla signals; errors carry a red
-- deny mark instead.

local GRAPHICS = require("scripts.const").GRAPHICS
local BASE = "__base__/graphics/icons/"
local SIGNAL = BASE .. "signal/"
local BADGE = GRAPHICS .. "grow-tool.png"
local DENY = SIGNAL .. "signal-deny.png"
local LOOK = BASE .. "radar.png"

local function icons(base, corner)
  return {
    { icon = base, icon_size = 64 },
    { icon = corner or BADGE, icon_size = 64, scale = 0.25, shift = { 8, 8 } },
  }
end

local GROUPS = {
  { "seb-verbs", "a" }, { "seb-options", "b" }, { "seb-answers", "c" }, { "seb-errors", "d" }, { "seb-sense", "e" },
}

-- {name, base icon, corner icon or nil (the badge)}
local SIGNALS = {
  ["seb-verbs"] = {
    { "seb-stamp", BASE .. "blueprint.png" },
    { "seb-grow", GRAPHICS .. "grow-tool.png", SIGNAL .. "signal-checked-green.png" },
    { "seb-remove", BASE .. "blueprint.png", DENY },
    { "seb-clear", BASE .. "deconstruction-planner.png" },
    { "seb-sense", LOOK },
    { "seb-capture", BASE .. "copy-paste-tool.png", SIGNAL .. "signal-checked-green.png" },
    { "seb-upgrade", BASE .. "upgrade-planner.png" },
    { "seb-find", SIGNAL .. "signal-map-marker.png", LOOK },
    { "seb-read", GRAPHICS .. "port.png", LOOK },
    { "seb-write", GRAPHICS .. "port.png", BASE .. "blueprint.png" },
  },
  ["seb-options"] = {
    { "seb-design", BASE .. "blueprint-book.png" },
    { "seb-instance", BASE .. "copy-paste-tool.png" },
    { "seb-absolute", SIGNAL .. "signal-map-marker.png" },
    { "seb-superforce", SIGNAL .. "signal-alert.png" },
    { "seb-count", SIGNAL .. "signal_C.png" },
    { "seb-radius", SIGNAL .. "signal-map-marker.png", SIGNAL .. "signal_R.png" },
    { "seb-grid-x", BASE .. "blueprint.png", GRAPHICS .. "socket-east.png" },
    { "seb-grid-y", BASE .. "blueprint.png", GRAPHICS .. "socket-south.png" },
    { "seb-spacing", SIGNAL .. "signal_S.png" },
    { "seb-pause", SIGNAL .. "signal-hourglass.png" },
    { "seb-stop", SIGNAL .. "signal-deny.png" },
    { "seb-cancel", BASE .. "deconstruction-planner.png", DENY },
    { "seb-grow-north", GRAPHICS .. "socket-north.png" },
    { "seb-grow-east", GRAPHICS .. "socket-east.png" },
    { "seb-grow-south", GRAPHICS .. "socket-south.png" },
    { "seb-grow-west", GRAPHICS .. "socket-west.png" },
  },
  ["seb-answers"] = {
    { "seb-ack", SIGNAL .. "signal-hourglass.png", SIGNAL .. "signal-checked-green.png" },
    { "seb-done", SIGNAL .. "signal-checked-green.png" },
    { "seb-error", DENY },
    { "seb-ghosts-left", SIGNAL .. "signal-ghost.png" },
    { "seb-open-sockets", GRAPHICS .. "socket.png" },
    { "seb-blocked-sockets", GRAPHICS .. "socket.png", DENY },
    { "seb-built", BASE .. "blueprint.png", SIGNAL .. "signal-checked-green.png" },
  },
  ["seb-errors"] = {
    { "seb-error-water", BASE .. "fluid/water.png", DENY },
    { "seb-error-cliff", BASE .. "cliff-explosives.png", DENY },
    { "seb-error-building", BASE .. "assembling-machine-1.png", DENY },
    { "seb-error-uncharted", LOOK, DENY },
    { "seb-error-materials", BASE .. "wooden-chest.png", DENY },
    { "seb-error-unknown-design", BASE .. "blueprint-book.png", DENY },
    { "seb-error-out-of-range", BASE .. "roboport.png", DENY },
    { "seb-error-not-found", SIGNAL .. "signal-map-marker.png", DENY },
    { "seb-error-invalid", SIGNAL .. "signal-alert.png", DENY },
    { "seb-error-no-resource", BASE .. "iron-ore.png", DENY },
    { "seb-error-probe", GRAPHICS .. "probe.png", DENY },
    { "seb-error-incomplete", SIGNAL .. "signal-ghost.png", DENY },
    { "seb-error-held-land", SIGNAL .. "signal-map-marker.png", SIGNAL .. "signal-alert.png" },
    { "seb-error-stopped", SIGNAL .. "signal-hourglass.png", DENY },
    { "seb-error-limit", BASE .. "blueprint-book.png", SIGNAL .. "signal-alert.png" },
  },
  ["seb-sense"] = {
    { "seb-sense-entities", BASE .. "assembling-machine-1.png", LOOK },
    { "seb-sense-ghosts", SIGNAL .. "signal-ghost.png", LOOK },
    { "seb-sense-resources", BASE .. "iron-ore.png", LOOK },
    { "seb-sense-trees", BASE .. "tree-01.png", LOOK },
    { "seb-sense-water", BASE .. "fluid/water.png", LOOK },
    { "seb-sense-enemies", BASE .. "biter-spawner.png", LOOK },
  },
}

local out = {}
for _, g in ipairs(GROUPS) do
  local subgroup, order = g[1], g[2]
  out[#out + 1] = { type = "item-subgroup", name = subgroup, group = "signals", order = "z[seb]-" .. order }
  for i, s in ipairs(SIGNALS[subgroup]) do
    out[#out + 1] = {
      type = "virtual-signal", name = s[1], icons = icons(s[2], s[3]),
      subgroup = subgroup, order = string.format("%02d", i),
    }
  end
end

data:extend(out)
