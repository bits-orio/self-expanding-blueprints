-- The test world: lab floors, a powered roboport network with fast robots and
-- a stocked storage chest, plus helpers that turn entity lists into blueprint
-- strings for the remote interface.

local rig = {}

rig.FORCE = "player"
rig.REMOTE = "self-expanding-blueprints"

local STOCK = {
  { "solar-panel", 400 }, { "medium-electric-pole", 200 }, { "small-electric-pole", 100 },
  { "accumulator", 50 }, { "assembling-machine-1", 20 }, { "assembling-machine-2", 20 },
  { "speed-module", 40 }, { "stone-brick", 400 }, { "transport-belt", 200 }, { "iron-chest", 50 },
  { "constant-combinator", 20 }, { "small-lamp", 50 }, { "stone-path", 0 }, { "rail", 40 },
}

function rig.call(fn, ...)
  return remote.call(rig.REMOTE, fn, ...)
end

-- Each scenario owns a region far from the others: rig.region(n) is its
-- origin, so networks and stamps never overlap.
function rig.region(n)
  return { x = (n % 4) * 400, y = math.floor(n / 4) * 400 + 400 }
end

function rig.offset(origin, dx, dy)
  return { x = origin.x + dx, y = origin.y + dy }
end

function rig.box(origin, left, top, right, bottom)
  return { left = origin.x + left, top = origin.y + top, right = origin.x + right, bottom = origin.y + bottom }
end

-- A scenario's site: lab floor around the region's origin and a network
-- north-west of it. Returns the origin.
function rig.site(surface, region)
  local o = rig.region(region)
  rig.floor(surface, rig.box(o, -60, -60, 60, 60))
  rig.network(surface, rig.offset(o, -25, -25))
  return o
end

-- Blueprint entity tables for test designs.
function rig.panel(x, y)
  return { name = "solar-panel", position = { x = x, y = y } }
end

function rig.socket(x, y, d, target)
  return { name = "seb-socket", position = { x = x, y = y }, direction = d, player_description = target }
end

function rig.entry(x, y, d)
  return { name = "seb-entry", position = { x = x, y = y }, direction = d }
end

-- Registers a blueprint built from entity tables; returns the design id.
function rig.design(entities, label, opts)
  opts = opts or {}
  opts.label = label
  local id, info = rig.call("register_design", rig.FORCE, rig.blueprint(entities, opts))
  return id, info
end

-- Entity ghosts on the surface in a box, as {name, x, y, direction} rows.
function rig.ghost_rows(surface, box)
  local rows = {}
  for _, g in pairs(surface.find_entities_filtered {
    area = { { box.left, box.top }, { box.right, box.bottom } }, type = "entity-ghost",
  }) do
    rows[#rows + 1] = { g.ghost_name, g.position.x, g.position.y, g.direction }
  end
  table.sort(rows, function(a, b) return a[1] .. a[2] .. a[3] < b[1] .. b[2] .. b[3] end)
  return rows
end

-- Generates chunks, lays lab tiles over the box and clears it.
function rig.floor(surface, box, tile)
  local centre = { x = (box.left + box.right) / 2, y = (box.top + box.bottom) / 2 }
  local radius = math.ceil(math.max(box.right - box.left, box.bottom - box.top) / 64) + 1
  surface.request_to_generate_chunks(centre, radius)
  surface.force_generate_chunk_requests()
  local tiles = {}
  for x = box.left, box.right - 1 do
    for y = box.top, box.bottom - 1 do
      tiles[#tiles + 1] = { name = tile or "lab-dark-1", position = { x, y } }
    end
  end
  surface.set_tiles(tiles)
  local area = { { box.left, box.top }, { box.right, box.bottom } }
  for _, e in pairs(surface.find_entities_filtered { area = area }) do
    if e.valid and e.type ~= "character" then e.destroy() end
  end
end

function rig.water(surface, box)
  rig.floor(surface, box, "water")
end

-- The game allows 64 forces, so scenarios that need no limits of their
-- own, only a force other than rig.FORCE, share this one; each keeps to
-- its own region and design labels.
rig.FREE_FORCE = "seb-test-free"

-- A force of its own for a case that sets per-force limits (set_limits),
-- with robots as fast as rig.FORCE's. Returns its name.
function rig.own_force(name)
  local force = game.forces[name] or game.create_force(name)
  force.worker_robots_speed_modifier = 8
  force.worker_robots_battery_modifier = 50
  return force.name
end

function rig.prepare()
  local surface = game.surfaces.nauvis
  game.forces.enemy.kill_all_units()
  game.map_settings.enemy_expansion.enabled = false
  local force = game.forces[rig.FORCE]
  force.worker_robots_speed_modifier = 8
  force.worker_robots_battery_modifier = 50
  -- Every case checks its own projects to the end, and they all share this
  -- force: it keeps every project that ended (cases.limits_growth tests the
  -- retention on a force of its own).
  rig.call("set_limits", rig.FORCE, { ended_projects = 0 })
  return surface
end

-- A roboport network centred on `at`: power, a roboport with robots and a
-- storage chest holding the test stock, for rig.FORCE or `force` (a name).
-- Returns the chest.
function rig.network(surface, at, stock, force)
  force = force or rig.FORCE
  local eei = surface.create_entity { name = "electric-energy-interface", position = { at.x, at.y - 6 }, force = force }
  eei.power_production = 1e9
  eei.electric_buffer_size = 1e10
  surface.create_entity { name = "medium-electric-pole", position = { at.x, at.y - 4 }, force = force }
  local port = surface.create_entity { name = "roboport", position = at, force = force }
  port.insert { name = "construction-robot", count = 100 }
  local chest = surface.create_entity { name = "storage-chest", position = { at.x + 3, at.y - 4 }, force = force }
  for _, s in ipairs(stock or STOCK) do
    if s[2] > 0 then chest.insert { name = s[1], count = s[2] } end
  end
  return chest
end

-- A blueprint export string from BlueprintEntity tables (and optional tiles,
-- snap grid and absolute grid offset). The label names the design when it is
-- registered.
function rig.blueprint(entities, opts)
  opts = opts or {}
  local inventory = game.create_inventory(1)
  local stack = inventory[1]
  stack.set_stack { name = "blueprint" }
  for i, e in ipairs(entities) do e.entity_number = e.entity_number or i end
  if #entities > 0 then stack.set_blueprint_entities(entities) end
  if opts.tiles then stack.set_blueprint_tiles(opts.tiles) end
  if opts.grid then stack.blueprint_snap_to_grid = opts.grid end
  if opts.absolute then
    stack.blueprint_absolute_snapping = true
    stack.blueprint_position_relative_to_grid = opts.absolute
  end
  if opts.label then stack.label = opts.label end
  local text = stack.export_stack()
  inventory.destroy()
  return text
end

-- The summaries of a project's instances, in id order.
function rig.instances_of(project_id)
  local list = {}
  for id = 1, 5000 do
    local inst = rig.call("get_instance", id)
    if inst and inst.project_id == project_id then list[#list + 1] = inst end
  end
  return list
end

-- The mod's render objects drawn in a box, counted by sprite name for
-- sprites and by type for the rest ("rectangle", "text", "line": a line by
-- where it starts).
function rig.drawn(surface, box)
  local counts = {}
  for _, object in pairs(rendering.get_all_objects(rig.REMOTE)) do
    local at = (object.type == "rectangle" and object.left_top) or (object.type == "line" and object.from) or object.target
    local p = at and at.position
    if object.surface.index == surface.index and p and p.x >= box.left and p.x < box.right
      and p.y >= box.top and p.y < box.bottom then
      local key = object.type == "sprite" and object.sprite or object.type
      counts[key] = (counts[key] or 0) + 1
    end
  end
  return counts
end

-- The union of the ghosts' collision boxes, rounded out to whole tiles.
function rig.tiles_of(ghosts)
  local box
  for _, g in pairs(ghosts) do
    local b = g.bounding_box
    local l, t = math.floor(b.left_top.x), math.floor(b.left_top.y)
    local r, bt = math.ceil(b.right_bottom.x), math.ceil(b.right_bottom.y)
    if not box then box = { left = l, top = t, right = r, bottom = bt }
    else
      box.left, box.top = math.min(box.left, l), math.min(box.top, t)
      box.right, box.bottom = math.max(box.right, r), math.max(box.bottom, bt)
    end
  end
  return box
end

-- Counts real (non-ghost) entities of a name in a box.
function rig.count(surface, box, name)
  return surface.count_entities_filtered {
    area = { { box.left, box.top }, { box.right, box.bottom } }, name = name,
  }
end

function rig.ghosts(surface, box)
  return surface.count_entities_filtered {
    area = { { box.left, box.top }, { box.right, box.bottom } }, type = "entity-ghost",
  }
end

return rig
