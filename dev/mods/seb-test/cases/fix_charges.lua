-- fix_charges.lua: every spot pays for the work it did, and a pool's step
-- stays small (regions 110-119). Every scenario with limits has a force of
-- its own; its share of server time is set once its designs are
-- registered, as registering is charged too. The free Find and count need
-- none (rig.FREE_FORCE), and cliff shares cases.fix_cliffs's force.
--   find:   a design of one chest and 1,000 probes whose last one holds only
--           beside ore: a Find on a small share answers much later than the
--           same Find with no limit, and at the same spot
--   grid:   a 16 x 16 Stamp grid of a design like it that fits nowhere runs
--           over many reads on a small share, then answers probe
--   repeat: a book holding one design 300 times makes a pool that lists it
--           once, and a plan's socket naming it tries it once
--   walk:   a pool's step that uses up the share stops, and the next one
--           goes on with the next design: the first that fits is stamped
--   ceiling: with no share limit, a pool's step stops once it has done the
--           part cap's worth (the cap lowered after registering), and the
--           next turn goes on: again the first design that fits is stamped
--   count:  a count reached closes a pool's socket as count-reached, even
--           when none of the pool's designs could be placed
--   cliff:  with cliff explosives researched, a cliff under a part holds the
--           copy at the materials gate until the network has an explosive;
--           then the robots blow the cliff up and build the copy

local check = require("lib.check")
local rig = require("lib.rig")
local builders = require("lib.builders")

local case = { name = "fix_charges" }

local FIND_SLOW, FIND_FREE, GRID, REPEAT, WALK, CLIFF, COUNT, CEILING = 110, 111, 112, 113, 114, 115, 116, 117
local D = defines.direction
local CHEST = { name = "iron-chest", position = { x = 0.5, y = 0.5 } }
local PROBES, COPIES = 1000, 300
-- The Find's probed design fits only where its last probe, two tiles east
-- of the chest, finds ore: beside the ore laid ORE_AT tiles east of the
-- search's centre, at the 140th spot it tries.
local ORE_AT, FOUND_AT = 8, 6
local BUILDER_AT = { -10.5, 0 }

local function name(text) return "fix_charges " .. text end

local function probe(x, y, signals)
  local filters = {}
  for i, s in ipairs(signals) do
    filters[i] = { index = i, type = s[1], name = s[2], quality = "normal", comparator = "=", count = 1 }
  end
  return {
    name = "seb-probe", position = { x = x, y = y },
    control_behavior = { sections = { sections = { { index = 1, filters = filters } } } },
  }
end

-- A chest under 999 probes that want no iron ore, and a last probe `dx`
-- tiles east that wants some: with dx = 0 it fits nowhere.
local function probed(dx)
  local list = { CHEST }
  for _ = 1, PROBES - 1 do list[#list + 1] = probe(0.5, 0.5, { { "item", "iron-ore" }, { "virtual", "signal-deny" } }) end
  list[#list + 1] = probe(0.5 + dx, 0.5, { { "item", "iron-ore" } })
  return list
end

-- 1,599 chests and a drill, which bare floor never fits.
local function big()
  local list = {}
  for x = 0, 38 do
    for y = 0, 40 do list[#list + 1] = { name = "wooden-chest", position = { x = x + 0.5, y = y + 0.5 } } end
  end
  list[#list + 1] = { name = "electric-mining-drill", position = { x = 40.5, y = 1.5 } }
  return list
end

local DRILL = { { name = "electric-mining-drill", position = { x = 1.5, y = 1.5 } } }
-- Two plugs: kept as a design, but one that can never be stamped.
local TWO_PLUGS = { CHEST, rig.entry(0.5, 1.5, D.north), rig.entry(0.5, -0.5, D.north) }

-- A labelled book of {label, entities} blueprints, as an export string.
local function book(label, blueprints)
  local inventory = game.create_inventory(1)
  local stack = inventory[1]
  stack.set_stack { name = "blueprint-book" }
  stack.label = label
  local inner = stack.get_inventory(defines.inventory.item_main)
  for i, entry in ipairs(blueprints) do
    inner.insert { name = "blueprint" }
    inner[i].import_stack(rig.blueprint(entry[2], { label = entry[1] }))
  end
  local text = stack.export_stack()
  inventory.destroy()
  return text
end

-- A force of the scenario's own and lab floor around its region's origin.
local function team(surface, region, force_name)
  local o = rig.region(region)
  rig.floor(surface, rig.box(o, -60, -60, 60, 60))
  return { origin = o, force = rig.own_force(force_name) }
end

local function register(force, entities, label)
  return rig.call("register_design", force, rig.blueprint(entities, { label = label }))
end

local function seed_with_socket(force, target, label)
  return register(force, { CHEST, rig.socket(1.5, 0.5, D.east, target) }, label)
end

local function find_site(surface, region, force_name, work, label)
  local t = team(surface, region, force_name)
  t.design = register(t.force, probed(2), label or force_name)
  for dx = ORE_AT, ORE_AT + 1 do
    surface.create_entity { name = "iron-ore", position = { t.origin.x + dx + 0.5, t.origin.y + 0.5 }, amount = 100 }
  end
  t.builder, t.program = builders.place(surface, rig.offset(t.origin, BUILDER_AT[1], BUILDER_AT[2]), t.force)
  rig.call("set_limits", t.force, { work = work })
  return t
end

local function grid_site(surface)
  local t = team(surface, GRID, "seb-fc-grid")
  t.design = register(t.force, probed(0), "seb-fc-grid")
  t.builder, t.program = builders.place(surface, rig.offset(t.origin, BUILDER_AT[1], BUILDER_AT[2]), t.force)
  rig.call("set_limits", t.force, { work = 500 })
  return t
end

local function repeat_site(surface)
  local t = team(surface, REPEAT, "seb-fc-repeat")
  local copies = {}
  for i = 1, COPIES do copies[i] = { "Repeated", { CHEST } } end
  t.ids, t.pool = rig.call("register_design", t.force, book("Repeat pool", copies))
  register(t.force, DRILL, "Repeated")
  t.seed = seed_with_socket(t.force, "Repeat pool", "Repeat seed")
  rig.call("set_limits", t.force, { work = 1 })
  return t
end

local function walk_site(surface)
  local t = team(surface, WALK, "seb-fc-walk")
  t.ids = rig.call("register_design", t.force, book("Walk pool", { { "Walk big", big() }, { "Walk fit", { CHEST } } }))
  t.seed = seed_with_socket(t.force, "Walk pool", "Walk seed")
  rig.call("set_limits", t.force, { work = 50 })
  return t
end

-- The part cap counts when a design is registered: lowered afterwards, it
-- only sizes a pool's step.
local function ceiling_site(surface)
  local t = team(surface, CEILING, "seb-fc-ceiling")
  t.ids = rig.call("register_design", t.force, book("Ceiling pool", { { "Ceiling drill", DRILL }, { "Ceiling fit", { CHEST } } }))
  t.seed = seed_with_socket(t.force, "Ceiling pool", "Ceiling seed")
  rig.call("set_limits", t.force, { design_parts = 1 })
  return t
end

local function count_site(surface)
  local t = team(surface, COUNT, rig.FREE_FORCE)
  t.ids = rig.call("register_design", t.force, book("Count pool", { { "Count two plugs", TWO_PLUGS } }))
  t.seed = seed_with_socket(t.force, "Count pool", "Count seed")
  return t
end

-- A cliff where the copy's chest goes, and a network with chests and no
-- explosive.
local function cliff_site(surface)
  -- Shared with cases.fix_cliffs, which needs cliff explosives too.
  local t = team(surface, CLIFF, "seb-fix-cliffs")
  game.forces[t.force].cliff_deconstruction_enabled = true
  t.design = register(t.force, { CHEST }, "seb-fc-cliff")
  t.cliff = surface.create_entity { name = "cliff", position = rig.offset(t.origin, 10, 10), cliff_orientation = "west-to-east" }
  t.chest = rig.network(surface, rig.offset(t.origin, -25, -25), { { "iron-chest", 10 } }, t.force)
  return t
end

function case.setup(surface)
  local s = {}
  storage.fix_charges = s
  s.find_slow = find_site(surface, FIND_SLOW, "seb-fc-find-slow", 500)
  s.find_free = find_site(surface, FIND_FREE, rig.FREE_FORCE, 0, "seb-fc-find-free")
  s.grid, s.rep, s.walk = grid_site(surface), repeat_site(surface), walk_site(surface)
  s.count, s.cliff, s.ceiling = count_site(surface), cliff_site(surface), ceiling_site(surface)
end

local function find_request(t)
  return { ["seb-find"] = 1, ["seb-design"] = t.design, ["seb-radius"] = 64, ["signal-X"] = t.origin.x,
    ["signal-Y"] = t.origin.y, ["seb-absolute"] = 1 }
end

local function start(t, design, extra)
  local params = { force = t.force, surface = game.surfaces.nauvis, design = design, charted_only = false }
  for k, v in pairs(extra) do params[k] = v end
  local id, reason = rig.call("start_project", params)
  check.truthy(name("project starts for " .. t.force), id, reason)
  return id
end

function case.start()
  local s = storage.fix_charges
  builders.send(s.find_slow.program, find_request(s.find_slow))
  builders.send(s.find_free.program, find_request(s.find_free))
  builders.send(s.grid.program, builders.grid(1, s.grid.design, 10, -1, 16))
  s.rep.plan = start(s.rep, s.rep.seed, { build_position = s.rep.origin, dry_run = true })
  -- No robots: these copies open their sockets as soon as they are placed.
  s.walk.project = start(s.walk, s.walk.seed, { build_position = s.walk.origin, max_instances = 2, materials = false,
    open_early = true })
  s.count.project = start(s.count, s.count.seed, { build_position = s.count.origin, max_instances = 1, materials = false,
    open_early = true })
  s.ceiling.project = start(s.ceiling, s.ceiling.seed, { build_position = s.ceiling.origin, max_instances = 2,
    materials = false, open_early = true })
  s.cliff.project = start(s.cliff, s.cliff.design, { position = rig.offset(s.cliff.origin, 10.5, 10.5), max_instances = 1 })
end

local function output(t) return builders.output(t.builder) end

local function running(out)
  return out["virtual/seb-ack"] == 1 and out["virtual/seb-done"] == nil and out["virtual/seb-error"] == nil
end

local function found_at(t, out)
  return out["virtual/seb-done"] == 1 and out["virtual/signal-X"] == t.origin.x + FOUND_AT
    and out["virtual/signal-Y"] == t.origin.y
end

local function project(id) return rig.call("get_project", id) or {} end

local function waited_busy(p)
  for _, entry in ipairs(p.history or {}) do
    if entry.kind == "waiting" and entry.reason == "busy" then return true end
  end
  return false
end

local function early()
  local s = storage.fix_charges
  check.truthy(name("a Find with no limit answers at once"), found_at(s.find_free, output(s.find_free)),
    check.show(output(s.find_free)))
  check.truthy(name("the same Find on a small share is still running"), running(output(s.find_slow)),
    check.show(output(s.find_slow)))
  check.truthy(name("a 16 x 16 Stamp grid of a heavily probed design takes more than one read"),
    running(output(s.grid)), check.show(output(s.grid)))
  local pools = rig.call("list_pools", s.rep.force)
  check.same(name("a book holding one design 300 times makes a pool listing it once"),
    { s.rep.ids and #s.rep.ids, pools["Repeat pool"] }, { COPIES, { s.rep.ids and s.rep.ids[1] } })
end

local function walked()
  local s = storage.fix_charges
  local plan = project(s.rep.plan)
  check.same(name("the plan tried the repeated design once and closed its socket"),
    { plan.count, plan.closed and plan.closed["no-resource"], plan.status and plan.status.level }, { 1, 1, "planned" })
  for key, text in pairs({ walk = "the share", ceiling = "the part cap's worth of work" }) do
    local t = s[key]
    local copies, p = rig.instances_of(t.project), project(t.project)
    check.same(name("a pool's step stopped by " .. text .. " goes on and stamps the first design that fits"),
      { #copies, copies[2] and copies[2].design_id }, { 2, t.ids and t.ids[2] })
    check.truthy(name("... after waiting its turn (" .. key .. ")"), waited_busy(p), check.show(p.history))
  end
  local c = project(s.count.project)
  check.same(name("a count reached closes a pool's socket as count-reached"),
    { (c.closed and c.closed["count-reached"] or 0) >= 1, c.closed and c.closed["invalid-design"], c.open_sockets },
    { true, nil, 0 })
end

local function cliff_held()
  local t = storage.fix_charges.cliff
  local p = project(t.project)
  local item = p.status and p.status.item
  check.same(name("a cliff under a part holds the copy for an explosive"),
    { p.count, p.gate, item and item.name, item and item.count }, { 0, "missing-materials", "cliff-explosives", 1 })
  t.chest.insert { name = "cliff-explosives", count = 1 }
end

local function cliff_built(surface)
  local t = storage.fix_charges.cliff
  local copy = rig.instances_of(t.project)[1] or {}
  check.same(name("with the explosive the robots clear the cliff and build the copy"),
    { copy.state, t.cliff.valid, t.chest.get_item_count("cliff-explosives") }, { "complete", false, 0 })
  check.eq(name("... and the chest stands where the cliff was"), rig.count(surface, rig.box(t.origin, 10, 10, 11, 11), "iron-chest"), 1)
end

local function late()
  local s = storage.fix_charges
  check.truthy(name("the Find on a small share answers too, at the same spot"), found_at(s.find_slow, output(s.find_slow)),
    check.show(output(s.find_slow)))
  local out = output(s.grid)
  check.truthy(name("the grid ends with probe"), builders.failed(out, 1, "probe"), check.show(out))
end

case.checks = { [240] = early, [300] = function() walked() cliff_held() end, [1500] = cliff_built, [4200] = late }

return case
