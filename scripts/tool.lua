-- Growing from the map. The window's Grow button puts the chosen design in
-- the cursor (grow_cursor.lua): its ghosts follow the pointer, and a click
-- grows the first copy exactly where they showed; the design comes back into
-- the hand, so each click starts another project. The area tool, a button of
-- its own, fills a dragged rectangle (a click on it grows from there too), a
-- right-drag retires the instances it touches, and a Shift + right-drag tries
-- the blocked sockets under it again (retry.lua). Works from map and remote
-- view: the surface acted on is the one the player looks at.

local const = require("scripts.const")
local scheduler = require("scripts.core.scheduler")
local geometry = require("scripts.core.geometry")
local registry = require("scripts.core.registry")
local library = require("scripts.core.library")
local footprints = require("scripts.core.footprints")
local instances = require("scripts.core.instances")
local projects = require("scripts.core.projects")
local limits = require("scripts.core.limits")
local cursor = require("scripts.cursor")
local grow_cursor = require("scripts.grow_cursor")
local twins = require("scripts.core.twins")
local loop = require("scripts.core.loop")
local outlines = require("scripts.gui.outlines")
local retry = require("scripts.core.retry")

local tool = {}

-- A click arrives as a selection of at most about one tile.
local CLICK_SIZE = 1.5
-- While the button stays down the engine pastes again at the same spot
-- every 6 ticks once the hand is refilled (measured on 2.1.23): a paste
-- where the last one was, within this many ticks of it, is that same click.
local REPEAT_TICKS = 15

-- The design the player chose in the window, still in their library.
local function chosen(player)
  local state = registry.player(player.index)
  return state.selected_design and library.get(player.force.index, state.selected_design)
end

-- The chosen design in hand; false when there is none or the hand is full.
function tool.give(player)
  local design = chosen(player)
  if not design then return false end
  local stack = cursor.free(player)
  local holds = stack and grow_cursor.write(stack, design)
  if not holds then return false end
  local state = registry.player(player.index)
  state.tool_design, state.held = design.id, holds
  return true
end

-- The area tool for the chosen design.
function tool.give_area(player)
  local design = chosen(player)
  if not design then return false end
  local stack = cursor.free(player)
  if not stack then return false end
  stack.set_stack { name = const.TOOL }
  stack.label = design.name
  registry.player(player.index).tool_design = design.id
  return true
end

-- A player who changes force keeps nothing of the old force's: no chosen
-- design, no grow tool or design in the cursor.
function tool.forget(player)
  local state = registry.player(player.index)
  state.selected_design, state.tool_design, state.design_open = nil, nil, nil
  local stack = player.cursor_stack
  if stack and stack.valid_for_read and (stack.name == const.TOOL or stack.name == const.GROW_BLUEPRINT) then
    stack.clear()
  end
end

local function ordered_directions(chosen_directions)
  local list = {}
  for _, d in ipairs(geometry.CARDINALS) do
    if chosen_directions[d] then list[#list + 1] = d end
  end
  return list
end

-- A fast fill opens each copy's sockets when it is placed, so it keeps this
-- many copies in flight instead of two.
local FAST_BUILDING = 8

-- The grow-toward directions as a paste turned the design (facing
-- `direction`, mirrored or not), so growth turns and flips with it.
local function turned_directions(list, direction, mirrored)
  local out = {}
  for i, d in ipairs(list) do
    if mirrored then d = (16 - d) % 16 end
    out[i] = (d + direction) % 16
  end
  return out
end

-- `where`: {point, direction, mirrored, superforced} (a click: the first
-- copy lands where the player's own blueprint would; a Ctrl + Shift paste
-- superforces the project as the window's option does) or {area,
-- from_right, from_bottom} (a drag, filled from the corner it started at
-- toward where it ended).
local function grow_params(player, surface, design, where)
  local options = registry.grow_options(player.index)
  local world = options.world_directions == true
  local params = {
    force_index = player.force.index, surface_index = surface.index, design_id = design.id,
    max_instances = registry.grow_count(options, where.area ~= nil),
    materials = options.materials,
    retire_depleted = options.retire_depleted == true, dry_run = options.dry_run == true,
    open_early = options.fast == true, max_building = options.fast and FAST_BUILDING or nil,
    superforce = options.superforce == true or where.superforced == true,
    preview_ghosts = options.dry_run and options.preview_ghosts or nil,
    mirrored = where.mirrored == true, world_directions = world, player_index = player.index,
  }
  if where.area then
    params.area, params.from_right, params.from_bottom = geometry.tile_box(where.area), where.from_right, where.from_bottom
    params.directions = { where.from_right and geometry.WEST or geometry.EAST, where.from_bottom and geometry.NORTH or geometry.SOUTH }
    -- The drag sets them, on the world's axis.
    params.world_directions = true
    return params
  end
  params.point, params.direction = where.point, where.direction
  params.directions = ordered_directions(options.directions)
  if not world then
    params.directions = turned_directions(params.directions, where.direction or geometry.NORTH, where.mirrored)
  end
  return params
end

-- A new plan past the team's limit of plans stopped its oldest ones: the
-- player is told which.
local function tell_dropped(player, dropped)
  local cap = limits.of(player.force.index, "plans")
  for _, plan in ipairs(dropped or {}) do player.print({ "seb-message.plan-replaced", plan.id, cap }) end
end

-- The design a paste grows: a flipped one grows the design's mirror twin.
local function pasted(player, where)
  local state = registry.player(player.index)
  local design = state.tool_design and library.get(player.force.index, state.tool_design)
  if not design then return nil, { "seb-message.no-design" } end
  if not where.mirrored then return design end
  local twin = twins.of(design)
  if not twin then return nil, { "seb-message.cannot-mirror", design.name } end
  return twin
end

-- A paste over copies already there: the first named, all of them flashed
-- on the map, so the player sees whose copies hold the spot.
local function tell_taken(player, taken)
  cursor.say(player, { "seb-message.seed-taken", outlines.label(storage.instances[taken[1]]) })
  outlines.flash(player, taken)
end

local function grow(player, surface, where)
  local design, refusal = pasted(player, where)
  if not design then return cursor.say(player, refusal) end
  local project, other, taken = projects.start(grow_params(player, surface, design, where))
  if taken then return tell_taken(player, taken) end
  -- A project started a moment ago, its first copy not down yet, is there:
  -- the player clicked twice.
  if not project and other == const.REASON.seed_occupied then return end
  if not project then return cursor.say(player, { "seb-reason." .. other }) end
  cursor.say(player, { "seb-message.growing", design.name })
  tell_dropped(player, other)
end

local function retire(player, event)
  local box = geometry.from_area(event.area)
  local count = 0
  for _, id in ipairs(footprints.overlapping(event.surface.index, box)) do
    local instance = storage.instances[id]
    if instance and instance.force_index == player.force.index and instances.retire(instance) then
      count = count + 1
    end
  end
  cursor.say(player, { "seb-message.retiring", count })
end

local function player_of(event)
  if event.item ~= const.TOOL then return nil end
  return game.get_player(event.player_index)
end

-- The area tool's selection as a click or a drag. A drag started at the
-- corner across from where it ended (the cursor then).
local function where_of(event)
  local box = geometry.from_area(event.area)
  local size = geometry.box_size(box)
  if size.x < CLICK_SIZE and size.y < CLICK_SIZE then return { point = geometry.box_center(box) } end
  local centre, ended = geometry.box_center(box), event.cursor_position or { x = box.right, y = box.bottom }
  return { area = box, from_right = ended.x < centre.x, from_bottom = ended.y < centre.y }
end

function tool.on_selected(event)
  local player = player_of(event)
  if player then grow(player, event.surface, where_of(event)) end
end

function tool.on_reverse_selected(event)
  local player = player_of(event)
  if player then retire(player, event) end
end

-- A Shift + right-drag: the force's blocked sockets under it are tried again.
function tool.on_alt_reverse_selected(event)
  local player = player_of(event)
  if not player then return end
  local box = geometry.from_area(event.area)
  -- A click covers the mark it lands on.
  local size = geometry.box_size(box)
  if size.x < CLICK_SIZE and size.y < CLICK_SIZE then
    local c = geometry.box_center(box)
    box = geometry.box(c.x - 1, c.y - 1, c.x + 1, c.y + 1)
  end
  local n = retry.area(player.force.index, event.surface.index, box, player)
  cursor.say(player, { "seb-message.retrying", n })
end

-- How a paste turned the design: its facing, and whether it is the mirror
-- image. A horizontal flip is the mirror facing the same way, a vertical one
-- the mirror half a turn further, and both only half a turn (measured against
-- the engine's own flips).
local function turned(event)
  local direction = event.direction
  if event.flip_vertical then direction = (direction + 8) % 16 end
  return direction, event.flip_horizontal ~= event.flip_vertical
end

-- Whether a paste is the last one again: the same spot, the button held.
local function repeated(state, position)
  local last = state.last_paste
  local same = last ~= nil and last.x == position.x and last.y == position.y and game.tick - last.tick <= REPEAT_TICKS
  state.last_paste = { x = position.x, y = position.y, tick = game.tick }
  return same
end

-- The design comes back into the hand the tick after a click, so the next
-- click starts the next project; not if the hand holds something else by
-- then, or the design is gone.
scheduler.register("refill-hand", function(item)
  local player = game.get_player(item.player_index)
  local stack = player and player.connected and player.cursor_stack
  if not stack or stack.valid_for_read or player.cursor_ghost or player.cursor_record then return end
  local design = library.get(player.force.index, item.design_id)
  local holds = design and grow_cursor.write(stack, design, item.turned)
  if not holds then return end
  local state = registry.player(player.index)
  state.tool_design, state.held = design.id, holds
end)

-- Changing view (remote view and back) the engine swaps a design in hand,
-- an item only a cursor holds, for its ghost, which pastes nothing: the
-- design goes back in the hand, turned and flipped as it was.
function tool.on_view_changed(player)
  local ghost = player.cursor_ghost
  if not (ghost and ghost.name and ghost.name.name == const.GROW_BLUEPRINT) then return end
  local state = registry.player(player.index)
  local design = state.tool_design and library.get(player.force.index, state.tool_design)
  player.cursor_ghost = nil
  local stack = design and player.cursor_stack
  if not stack then return end
  local holds = grow_cursor.write(stack, design, state.held)
  if holds then state.held = holds end
end

-- The turn and flip of a paste of what the hand held, itself turned and
-- flipped as `held`: the paste's own on top (a flip turns the other way).
local function combined(held, direction, mirrored)
  local d, m = held and held.direction or 0, held and held.mirrored == true
  return (direction + (mirrored and -d or d)) % 16, m ~= mirrored
end

-- A click with the design in hand. An empty cursor calls the engine's paste
-- off, so nothing of it is built; the copy grows from where its ghosts
-- showed, turned and flipped as the player turned and flipped them. The
-- design is handed back next tick (a hand refilled within the click lets
-- the engine paste it). Over water the engine refuses a plain click; a
-- Shift paste reaches here, and a Ctrl + Shift one superforces the project.
function tool.on_pre_build(event)
  local player = game.get_player(event.player_index)
  if not (player and grow_cursor.held(player)) then return end
  local state = registry.player(player.index)
  player.clear_cursor()
  local direction, mirrored = combined(state.held, turned(event))
  scheduler.at(game.tick + 1, {
    kind = "refill-hand", player_index = player.index, design_id = state.tool_design,
    turned = { direction = direction, mirrored = mirrored },
  })
  if repeated(state, event.position) then return end
  grow(player, player.surface, {
    point = event.position, direction = direction, mirrored = mirrored,
    superforced = event.build_mode == defines.build_mode.superforced,
  })
end

-- A project the player started that ended before building anything: they
-- are told why at the cursor and in chat, with a map link to where it began,
-- and the project goes, so there is no row left to delete.
loop.hooks.nothing_built = function(project)
  if not project.player_index then return end
  local player = game.get_player(project.player_index)
  if player and player.connected then
    local note, surface = project.nothing_built, game.get_surface(project.surface_index)
    local at = note.position
    local gps = (at and surface) and string.format("[gps=%d,%d,%s]", math.floor(at.x), math.floor(at.y), surface.name) or ""
    local design = library.get(project.force_index, project.design_id)
    local why = note.reason and { "seb-reason." .. note.reason } or ""
    local key = project.dry_run and "seb-message.nothing-planned" or "seb-message.nothing-built"
    cursor.say(player, { "seb-message.nothing-grew", why })
    player.print({ key, design and design.name or "?", why, gps })
  end
  projects.discard(project)
end

return tool
