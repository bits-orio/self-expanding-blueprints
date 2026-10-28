-- vanish.lua: a copy with nothing of it left is released (D55): no entity
-- of it stands and no ghost or request of it waits, its parts removed by
-- hand, say. Its record goes, on_instance_retired is raised, its spot is
-- free and nothing else is removed.
--   whole:  both chests of a built copy destroyed: released, spot free
--   half:   one of the two destroyed: the copy stays
--   ghosts: its ghosts destroyed before any robot came: released, not left
--           incomplete holding its spot
--   tiles:  a copy of tiles only places no entity: it stays

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "vanish" }

local REGION = 189
local PAIR = { { name = "iron-chest", position = { x = 0.5, y = 0.5 } }, { name = "iron-chest", position = { x = 2.5, y = 0.5 } } }
local PAVED = {
  { name = "stone-path", position = { x = 0, y = 0 } }, { name = "stone-path", position = { x = 1, y = 0 } },
}

local function stamp(design, dx, dy)
  local id, reason = rig.call("stamp", {
    force = rig.FORCE, surface = game.surfaces.nauvis, design = design, position = rig.offset(rig.region(REGION), dx, dy),
  })
  check.truthy("vanish stamps", id, reason)
  return id
end

local function in_footprint(id, filter)
  local fp = rig.call("get_instance", id).footprint
  filter.area = { { fp.left, fp.top }, { fp.right, fp.bottom } }
  return game.surfaces.nauvis.find_entities_filtered(filter)
end

function case.setup(surface)
  rig.site(surface, REGION)
  storage.vanish = {
    pair = rig.design(PAIR, "Vanish pair"),
    paved = rig.design({}, "Vanish paved", { tiles = PAVED }),
    retired = {},
  }
  check.truthy("vanish designs registered", storage.vanish.pair and storage.vanish.paved)
end

function case.start()
  local v = storage.vanish
  v.whole = stamp(v.pair, 0.5, 0.5)
  v.half = stamp(v.pair, 0.5, 4.5)
  v.ghosts = stamp(v.pair, 0.5, 8.5)
  v.tiles = stamp(v.paved, 0.5, 12.5)
  for _, ghost in pairs(in_footprint(v.ghosts, { type = "entity-ghost" })) do ghost.destroy() end
end

function case.on_event(name, payload)
  local v = storage.vanish
  if name == "on_instance_retired" and v then v.retired[payload.instance_id] = true end
end

-- Both chests of one copy go, one chest of another.
local function remove_parts()
  local v = storage.vanish
  for _, id in ipairs({ v.whole, v.half }) do
    local inst = rig.call("get_instance", id)
    check.eq("vanish built before removal " .. id, inst and inst.state, "complete")
  end
  for _, chest in pairs(in_footprint(v.whole, { name = "iron-chest" })) do chest.destroy() end
  in_footprint(v.half, { name = "iron-chest" })[1].destroy()
end

local function released()
  local v = storage.vanish
  check.eq("vanish emptied copy released", rig.call("get_instance", v.whole), nil)
  check.truthy("vanish emptied copy raised its retirement", v.retired[v.whole])
  local half = rig.call("get_instance", v.half)
  check.truthy("vanish copy with a part left stays", half and half.state == "complete", half and half.state)
  check.eq("vanish copy whose ghosts were removed released", rig.call("get_instance", v.ghosts), nil)
  local tiles = rig.call("get_instance", v.tiles)
  check.truthy("vanish copy of tiles only stays", tiles ~= nil and tiles.state == "complete", tiles and tiles.state)
  local again = stamp(v.pair, 0.5, 0.5)
  check.truthy("vanish spot free for another copy", again)
end

case.checks = { [900] = remove_parts, [1200] = released }

return case
