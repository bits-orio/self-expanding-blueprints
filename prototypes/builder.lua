-- The blueprint builder (DESIGN.md section 4): a combinator that takes
-- requests on its input (red and green, summed) and answers on its output.
-- It is a decider combinator underneath, for the two connectors and the
-- look; its own decider settings stay empty and its GUI is closed to
-- players. What it outputs comes from a hidden constant combinator the
-- script places on it and wires to its output (seb-builder-output).

local GRAPHICS = require("scripts.const").GRAPHICS
local DECIDER = data.raw["decider-combinator"]["decider-combinator"]
local CONSTANT = data.raw["constant-combinator"]["constant-combinator"]

local ICONS = {
  { icon = "__base__/graphics/icons/decider-combinator.png", icon_size = 64 },
  { icon = GRAPHICS .. "grow-tool.png", icon_size = 64, scale = 0.25, shift = { 8, 8 } },
}
local TINT = { r = 0.62, g = 0.80, b = 1.00, a = 1 }

-- Tints every picture layer of a Sprite4Way, so the builder is told apart
-- from a decider at a glance.
local function tint_layers(node)
  if type(node) ~= "table" then return end
  if node.filename then node.tint = TINT end
  for _, child in pairs(node) do tint_layers(child) end
end

local builder = table.deepcopy(DECIDER)
builder.name = "seb-builder"
builder.icon = nil
builder.icons = ICONS
builder.minable = { mining_time = 0.1, result = "seb-builder" }
builder.fast_replaceable_group = nil
-- Its decider settings are not its own: nothing is copied onto it.
builder.allow_copy_paste = false
builder.next_upgrade = nil
builder.corpse = "decider-combinator-remnants"
-- It answers through script and needs no power.
builder.energy_source = { type = "void" }
tint_layers(builder.sprites)

local output = table.deepcopy(CONSTANT)
output.name = "seb-builder-output"
output.icons = ICONS
output.icon = nil
output.flags = {
  "placeable-off-grid", "not-blueprintable", "not-deconstructable", "not-on-map", "hide-alt-info",
  "not-repairable", "not-in-kill-statistics", "not-flammable", "no-automated-item-removal",
  "no-automated-item-insertion", "not-upgradable",
}
output.hidden = true
output.hidden_in_factoriopedia = true
output.minable = nil
output.selectable_in_game = false
output.collision_mask = { layers = {} }
output.collision_box = { { -0.1, -0.1 }, { 0.1, 0.1 } }
output.selection_box = { { -0.1, -0.1 }, { 0.1, 0.1 } }
output.sprites = nil
output.activity_led_sprites = nil
output.draw_circuit_wires = false
output.fast_replaceable_group = nil
output.next_upgrade = nil
output.corpse = nil
output.dying_explosion = nil
output.created_effect = nil

data:extend({
  builder,
  output,
  {
    type = "item", name = "seb-builder", icons = ICONS, subgroup = "circuit-network",
    order = "c[combinators]-z[seb-builder]", place_result = "seb-builder", stack_size = 50,
  },
  {
    type = "recipe", name = "seb-builder", enabled = false,
    ingredients = { { type = "item", name = "decider-combinator", amount = 1 }, { type = "item", name = "electronic-circuit", amount = 5 } },
    results = { { type = "item", name = "seb-builder", amount = 1 } },
  },
})

local tech = data.raw.technology["circuit-network"]
if tech then
  tech.effects = tech.effects or {}
  table.insert(tech.effects, { type = "unlock-recipe", recipe = "seb-builder" })
end
