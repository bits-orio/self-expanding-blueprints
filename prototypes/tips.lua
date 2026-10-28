-- Tips and Tricks entries (DESIGN.md "Remote view and teaching"): one entry
-- per use case, each with a simulation that runs the mod itself. The
-- entries live in prototypes/tips/ by topic: growing (the click, sides,
-- areas, obstacles, materials, removing), markers (what a player draws into
-- a design) and advanced (plans, updates and the circuit layer).
-- prototypes/tips/setup.lua is what their simulations share.

local growing = require("prototypes.tips.growing")
local markers = require("prototypes.tips.markers")
local advanced = require("prototypes.tips.advanced")

data:extend({
  { type = "tips-and-tricks-item-category", name = "self-expanding-blueprints", order = "z-[self-expanding-blueprints]" },
})
data:extend(growing)
data:extend(markers)
data:extend(advanced)
