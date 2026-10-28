-- A stand-in for Land Title Registry's blocker entity: the mod names the
-- refusal "outside held land" when one is in a part's way.
local blocker = table.deepcopy(data.raw["simple-entity-with-owner"]["simple-entity-with-owner"])
blocker.name = "ltr-cell-wilderness"
blocker.minable = nil
data:extend({ blocker })

-- Stand-ins for Negative Space's two markers (same names; the mod reads
-- them as Keep clear and as left out): a box that collides with objects,
-- and one that collides with nothing. Items so a blueprint can hold them.
local function stand_in(name, layers)
  local e = table.deepcopy(data.raw["simple-entity-with-owner"]["simple-entity-with-owner"])
  e.name = name
  e.collision_box = { { -0.4, -0.4 }, { 0.4, 0.4 } }
  e.collision_mask = { layers = layers }
  e.placeable_by = { item = name, count = 1 }
  e.minable = { mining_time = 0.1 }
  local item = table.deepcopy(data.raw.item["iron-chest"])
  item.name = name
  item.place_result = name
  return e, item
end
local ns, ns_item = stand_in("negative-space", { object = true, is_lower_object = true })
local auto, auto_item = stand_in("negative-space-auto", {})
data:extend({ ns, ns_item, auto, auto_item })
