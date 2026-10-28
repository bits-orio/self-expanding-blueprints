-- Candidate marker for S1: a rotatable 1x1 entity with an empty collision mask.
-- fast_replaceable_group is cleared so a marker ghost never counts as a fast
-- replace of a real constant combinator (that would confound the overlap cases).
local marker = table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
marker.name = "seb-spike-marker"
marker.collision_mask = {layers = {}}
marker.minable = {mining_time = 0.1}
marker.fast_replaceable_group = nil
marker.next_upgrade = nil

data:extend({
  marker,
  {
    type = "item",
    name = "seb-spike-marker",
    icon = "__base__/graphics/icons/constant-combinator.png",
    stack_size = 50,
    place_result = "seb-spike-marker",
    flags = {"only-in-cursor"},
    hidden = true,
  },
})
