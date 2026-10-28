-- fix_updates.lua: updates in place wait their turn, and depleted copies of
-- forgotten projects still go (regions 160-169, D44, D45).
--   queued:    a project's 40 outdated copies, on a force with a small
--              share of server time, are updated a few at a time over many
--              scheduler runs and all end at the new version; asking again
--              queues none twice, and a copy removed meanwhile is passed over
--   research:  a research upgrade of 40 copies goes the same way
--   big:       a copy of 1,600 lamps is updated in one short piece (INFO);
--              a version whose blueprint coordinates moved 3 tiles is laid
--              where the copy stands, every lamp kept
--   forgotten: a finished mining project that removes copies whose ore runs
--              out is forgotten (ended_projects = 1); its copy still goes
--              when the ore is gone, and its record with it
--   updated:   after an update in place, a forgotten finished project's
--              copy still goes when dry; a stopped one's stays

local check = require("lib.check")
local rig = require("lib.rig")

local case = { name = "fix_updates" }

local QUEUED, RESEARCH, BIG, FORGOTTEN, UPDATED = 160, 161, 162, 163, 164
local COPIES = 40
local SHARE = 20   -- microseconds a tick: a copy's update takes about 30 ticks of it
local PAIR = { { name = "small-lamp", position = { x = 0.5, y = 0.5 } }, { name = "small-lamp", position = { x = 1.5, y = 0.5 } } }
local PAIR_V2 = { { name = "small-lamp", position = { x = 0.5, y = 0.5 } }, { name = "iron-chest", position = { x = 1.5, y = 0.5 } } }
local STOCK = { { "small-lamp", 100 }, { "iron-chest", 60 }, { "solar-panel", 20 } }
local DRILL = { name = "electric-mining-drill", position = { x = 1.5, y = 1.5 } }   -- mines tiles -1..3
local CHEST = { name = "iron-chest", position = { x = 4.5, y = 1.5 } }
local CELL = { rig.panel(1.5, 1.5) }
local MINE_STOCK = { { "electric-mining-drill", 10 }, { "iron-chest", 10 }, { "solar-panel", 20 } }
local SIDE = 40   -- the big design: SIDE x SIDE lamps

local function name(key) return "fix_updates " .. key end

local function s() return storage.fix_updates end

local function team(force_name, limits, region, stock)
  local force = rig.own_force(force_name)
  rig.call("set_limits", force, limits)
  local o = rig.region(region)
  rig.floor(game.surfaces.nauvis, rig.box(o, -60, -60, 60, 60))
  rig.network(game.surfaces.nauvis, rig.offset(o, -25, -25), stock, force)
  return force, o
end

local function design(force, entities, label)
  return rig.call("register_design", force, rig.blueprint(entities, { label = label }))
end

local function start(force, d, extra)
  local params = { force = force, surface = game.surfaces.nauvis, design = d, charted_only = false }
  for k, v in pairs(extra) do params[k] = v end
  return rig.call("start_project", params)
end

local function lamps(n, dx)
  local list = {}
  for i = 0, n - 1 do
    list[#list + 1] = { name = "small-lamp", position = { x = i % SIDE + 0.5 + (dx or 0), y = math.floor(i / SIDE) + 0.5 } }
  end
  return list
end

local function ore(o, left, top, right, bottom)
  for x = left, right - 1 do
    for y = top, bottom - 1 do
      game.surfaces.nauvis.create_entity { name = "iron-ore", position = { o.x + x + 0.5, o.y + y + 0.5 }, amount = 50 }
    end
  end
end

local function deplete(o, left, top, right, bottom)
  local area = { { o.x + left, o.y + top }, { o.x + right, o.y + bottom } }
  for _, r in pairs(game.surfaces.nauvis.find_entities_filtered { area = area, name = "iron-ore" }) do r.deplete() end
end

-- The copies of a project, as on_instance_completed named them.
local function copies_of(project_id)
  local list = {}
  for id in pairs(s().copies[project_id] or {}) do
    local inst = rig.call("get_instance", id)
    if inst then list[#list + 1] = inst end
  end
  table.sort(list, function(a, b) return a.id < b.id end)
  return list
end

local function at_version(project_id, version)
  local n = 0
  for _, inst in ipairs(copies_of(project_id)) do
    if inst.version == version then n = n + 1 end
  end
  return n
end

function case.on_event(event_name, payload)
  local state = storage.fix_updates
  if event_name ~= "on_instance_completed" or not (state and payload.project_id) then return end
  state.copies[payload.project_id] = state.copies[payload.project_id] or {}
  state.copies[payload.project_id][payload.instance_id] = true
end

function case.setup(surface)
  storage.fix_updates = { copies = {} }
  local t = s()
  t.queued, t.queued_o = team("fu-queued", { work = SHARE, ended_projects = 0 }, QUEUED, STOCK)
  t.research, t.research_o = team("fu-research", { work = SHARE, ended_projects = 0 }, RESEARCH, STOCK)
  t.queued_design = design(t.queued, PAIR, "fu pair")
  t.research_design = design(t.research, PAIR, "fu pair")
  local big_o = rig.region(BIG)
  rig.floor(surface, rig.box(big_o, -60, -60, 60, 60))
  t.big_design = rig.design(lamps(SIDE * SIDE), "fu big")
  t.mine, t.mine_o = team("fu-mine", { ended_projects = 1 }, FORGOTTEN, MINE_STOCK)
  t.mine2, t.mine2_o = team("fu-mine2", { ended_projects = 1 }, UPDATED, MINE_STOCK)
  ore(t.mine_o, -1, -1, 4, 4)
  ore(t.mine2_o, -1, -1, 4, 4)
  ore(t.mine2_o, 19, -1, 24, 4)
  t.miner, t.mine_cell = design(t.mine, { DRILL, CHEST }, "fu miner"), design(t.mine, CELL, "fu cell")
  t.miner2, t.mine2_cell = design(t.mine2, { DRILL, CHEST }, "fu miner"), design(t.mine2, CELL, "fu cell")
end

local function fill(force, d, o)
  return start(force, d, {
    area = rig.box(o, 0, 0, 10, 8), max_instances = COPIES, materials = false, open_early = true, max_building = COPIES,
  })
end

function case.start(surface)
  local t = s()
  t.queued_p = fill(t.queued, t.queued_design, t.queued_o)
  t.research_p = fill(t.research, t.research_design, t.research_o)
  t.big = rig.call("stamp", { force = rig.FORCE, surface = surface, design = t.big_design, position = rig.offset(rig.region(BIG), 0.5, 0.5),
    charted_only = false })
  t.mine_p = start(t.mine, t.miner, { build_position = t.mine_o, max_instances = 1, retire_depleted = true })
  t.kept_p = start(t.mine2, t.miner2, { build_position = t.mine2_o, max_instances = 1, retire_depleted = true })
  t.stopped_p = start(t.mine2, t.miner2,
    { build_position = rig.offset(t.mine2_o, 20, 0), max_instances = 1, retire_depleted = true })
  check.truthy(name("projects and stamps start"),
    t.queued_p and t.research_p and t.big and t.mine_p and t.kept_p and t.stopped_p)
end

-- Every copy is built: v2 swaps a lamp for a chest. The project asks for
-- all its copies at once, the research names the same for its own.
local function ask(surface)
  local t = s()
  check.eq(name("queued project filled"), #copies_of(t.queued_p), COPIES)
  check.eq(name("research project filled"), #copies_of(t.research_p), COPIES)
  design(t.queued, PAIR_V2, "fu pair")
  local queued, refused = rig.call("update_project", t.queued_p)
  check.same(name("update_project queues every outdated copy"), { queued, refused }, { COPIES, 0 })
  local again = rig.call("update_project", t.queued_p)
  check.eq(name("asking again queues none twice"), again, 0)
  check.eq(name("nothing is updated in the tick it is asked for"), at_version(t.queued_p, 2), 0)
  local list = copies_of(t.queued_p)
  t.removed = list[#list].id
  rig.call("remove_instance", t.removed)
  design(t.research, PAIR_V2, "fu pair")
  rig.call("set_upgrade_research", t.research, t.research_design, "steel-processing")
  game.forces[t.research].technologies["steel-processing"].researched = true
  check.eq(name("research updates nothing in its own tick"), at_version(t.research_p, 2), 0)
end

-- A second later: a few are done, most still wait their team's turn.
local function a_second_later()
  local t = s()
  local queued, research = at_version(t.queued_p, 2), at_version(t.research_p, 2)
  check.info(name("a second after asking: " .. queued .. " project copies and " .. research .. " research copies updated"))
  check.truthy(name("project copies update a few at a time"), queued > 0 and queued < COPIES / 2, queued)
  check.truthy(name("research copies update a few at a time"), research > 0 and research < COPIES / 2, research)
end

local function last_entry(project_id)
  local p = rig.call("get_project", project_id)
  local list = p and p.history or {}
  return list[#list] or {}
end

local function all_done()
  local t = s()
  local list = copies_of(t.queued_p)
  local complete = 0
  for _, inst in ipairs(list) do
    if inst.version == 2 and inst.state == "complete" then complete = complete + 1 end
  end
  check.eq(name("every queued copy ends updated and built"), complete, COPIES - 1)
  check.eq(name("the copy removed while queued was passed over"), rig.call("get_instance", t.removed), nil)
  local entry = last_entry(t.queued_p)
  check.same(name("history says how the batch went"), { entry.kind, entry.copies, entry.refused }, { "updated", COPIES - 1, 0 })
  check.eq(name("every research copy ends updated"), at_version(t.research_p, 2), COPIES)
end

-- The big copy, built by script, moves to a version with one lamp more.
local function big_update(surface)
  local t = s()
  local inst = rig.call("get_instance", t.big)
  local fp = inst.footprint
  for _, ghost in pairs(surface.find_entities_filtered { area = { { fp.left, fp.top }, { fp.right, fp.bottom } }, type = "entity-ghost" }) do
    ghost.revive { raise_revive = true }
  end
  rig.design(lamps(SIDE * SIDE + 1), "fu big")
  local profiler = helpers.create_profiler()
  local ok, why = rig.call("update_instance", t.big)
  profiler.stop()
  log({ "", "SEB_TEST INFO ", name("a copy of " .. SIDE * SIDE .. " lamps updated in "), profiler })
  check.eq(name("the big copy is updated"), ok, true, why)
  local after = rig.call("get_instance", t.big)
  check.same(name("the big copy keeps every lamp it had"), { after.version, after.entity_count }, { 2, SIDE * SIDE })
  -- The same lamps, their blueprint coordinates 3 tiles to the right.
  rig.design(lamps(SIDE * SIDE + 1, 3), "fu big")
  local moved, because = rig.call("update_instance", t.big)
  check.eq(name("the moved version is laid over the copy"), moved, true, because)
  local again = rig.call("get_instance", t.big)
  check.same(name("where the copy stands, every lamp kept"),
    { again.version, again.entity_count, again.footprint.left, again.footprint.top },
    { 3, SIDE * SIDE, after.footprint.left, after.footprint.top })
end

-- Every mining project has finished its copy (fu-mine2 kept only the newer
-- of its two: ended_projects = 1). One is stopped; ending three more
-- projects forgets the rest.
local function forget()
  local t = s()
  local mine = rig.call("get_project", t.mine_p)
  check.eq(name("the mining project finished"), mine and mine.state, "finished")
  t.mine_copy, t.kept_copy = (copies_of(t.mine_p)[1] or {}).id, (copies_of(t.kept_p)[1] or {}).id
  t.stopped_copy = (copies_of(t.stopped_p)[1] or {}).id
  local kept, stopped = rig.call("get_instance", t.kept_copy), rig.call("get_instance", t.stopped_copy)
  check.same(name("the other mining copies are built"), { kept and kept.state, stopped and stopped.state },
    { "complete", "complete" })
  rig.call("stop_project", t.stopped_p)
  for i, team_name in ipairs({ t.mine, t.mine, t.mine2 }) do
    local cell = team_name == t.mine and t.mine_cell or t.mine2_cell
    local o = team_name == t.mine and t.mine_o or t.mine2_o
    rig.call("stop_project", start(team_name, cell, { build_position = rig.offset(o, 30, 10 + 4 * i), materials = false, max_instances = 1 }))
  end
  local gone = { rig.call("get_project", t.mine_p), rig.call("get_project", t.kept_p), rig.call("get_project", t.stopped_p) }
  check.same(name("the mining projects are forgotten"), gone, {})
  -- The same miner again: both remaining copies are updated in place.
  design(t.mine2, { DRILL, CHEST }, "fu miner")
  check.eq(name("the forgotten finished copy is updated"), rig.call("update_instance", t.kept_copy), true)
  check.eq(name("the forgotten stopped copy is updated"), rig.call("update_instance", t.stopped_copy), true)
  deplete(t.mine_o, -1, -1, 4, 4)
  deplete(t.mine2_o, -1, -1, 4, 4)
  deplete(t.mine2_o, 19, -1, 24, 4)
end

local function drills(o, dx)
  return rig.count(game.surfaces.nauvis, rig.box(o, dx - 2, -2, dx + 6, 6), "electric-mining-drill")
end

local function dried()
  local t = s()
  check.eq(name("a forgotten finished project's dry copy goes"), drills(t.mine_o, 0), 0)
  check.eq(name("and its record is forgotten"), rig.call("get_instance", t.mine_copy), nil)
  check.eq(name("updated, a forgotten finished project's dry copy goes"), drills(t.mine2_o, 0), 0)
  check.eq(name("updated, a forgotten stopped project's dry copy stays"), drills(t.mine2_o, 20), 1)
  local stopped = rig.call("get_instance", t.stopped_copy)
  check.eq(name("that copy is complete"), stopped and stopped.state, "complete")
end

case.checks = {
  [1140] = forget,
  [1200] = ask,
  [1260] = a_second_later,
  [1320] = big_update,
  [3600] = dried,
  [6000] = all_done,
}

return case
