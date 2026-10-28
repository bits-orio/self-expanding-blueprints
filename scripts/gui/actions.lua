-- Routes GUI events by the element's tags.seb action name.

local const = require("scripts.const")
local registry = require("scripts.core.registry")
local library = require("scripts.core.library")
local books = require("scripts.core.books")
local budget = require("scripts.core.budget")
local projects = require("scripts.core.projects")
local window = require("scripts.gui.window")
local projects_view = require("scripts.gui.projects_view")
local preview = require("scripts.gui.preview")
local copies_view = require("scripts.gui.copies_view")
local instances = require("scripts.core.instances")
local update = require("scripts.core.update")
local tool = require("scripts.tool")
local markers = require("scripts.markers")
local marker_tools = require("scripts.marker_tools")
local locate = require("scripts.locate")
local outlines = require("scripts.gui.outlines")
local naming = require("scripts.core.naming")
local cursor = require("scripts.cursor")
local research = require("scripts.core.research")
local help_view = require("scripts.gui.help_view")
local design_text = require("scripts.gui.design_text")
local book_queue = require("scripts.gui.book_queue")
local previews = require("scripts.core.previews")

-- How long a project's copies stay outlined after its locate button.
local LOCATE_OUTLINE_TICKS = 600

local actions = {}

-- One blueprint registers at once, as the next version when `name` is
-- taken, while the team's share of server time lasts (budget.lua); a book
-- goes through book_queue.lua. Returns the design, or nil once the player
-- is told why not.
local function register(player, source, name)
  local force_index = player.force.index
  if not budget.ready(force_index) then return cursor.say(player, { "seb-reason.busy" }) end
  if library.oversized(force_index, source) then
    return cursor.say(player, design_text.error(const.REASON.design_too_big, force_index))
  end
  local design, reason = library.register_string(force_index, books.export_of(source), name)
  if not design then return cursor.say(player, design_text.error(reason, force_index)) end
  player.print({ "seb-message.registered", design.name, design.version })
  return design
end

local function add_design(player)
  local source = cursor.blueprint(player)
  if not source then return cursor.say(player, { "seb-message.hold-blueprint" }) end
  if not books.is_single_blueprint(source) then return book_queue.start(player, source) end
  local design = register(player, source)
  if not design then return end
  registry.player(player.index).selected_design = design.id
  window.refresh_designs(player.force.index, design.id)
end

local function update_design(player, tags)
  local design = library.get(player.force.index, tags.design)
  local source = cursor.blueprint(player)
  if not (design and source) then return cursor.say(player, { "seb-message.hold-blueprint" }) end
  if not books.is_single_blueprint(source) then return cursor.say(player, { "seb-error.book-not-blueprint" }) end
  local updated = register(player, source, design.name)
  if updated then window.refresh_designs(player.force.index, updated.id) end
end

-- The project's own change redraws its row (projects.hooks.changed); a row
-- naming a project that is gone is redrawn here.
local function with_project(fn)
  return function(player, tags)
    local project = registry.project(tags.project)
    if project and project.force_index == player.force.index then return fn(project, player) end
    window.refresh(player)
  end
end

-- A copy of the player's own force, from an element's tags.
local function with_copy(fn)
  return function(player, tags)
    local instance = storage.instances[tags.instance]
    if instance and instance.force_index == player.force.index then return fn(instance, player) end
    copies_view.refresh(player)
  end
end

local click = {
  close = function(player) window.close(player) end,
  ["add-design"] = add_design,
  ["update-design"] = update_design,
  ["select-design"] = function(player, tags) window.open_design(player, tags.design) end,
  ["back-to-designs"] = function(player) window.show_designs(player) end,
  ["grow-more"] = function(player)
    local options = registry.grow_options(player.index)
    options.more = not options.more
    window.refresh_grow(player)
  end,
  ["delete-design"] = function(player, tags)
    local design = library.get(player.force.index, tags.design)
    if design then library.delete(design) end
    window.refresh_designs(player.force.index, tags.design)
  end,
  ["give-marker"] = function(player, tags) markers.give(player, tags.item) end,
  ["give-marker-tool"] = function(player, tags) marker_tools.give(player, tags.item) end,
  -- Every design as one blueprint book in the cursor.
  ["export-library"] = function(player)
    if #library.list(player.force.index) == 0 then return cursor.say(player, { "seb-message.no-designs" }) end
    local stack = cursor.free(player)
    if stack then books.fill_book(player.force.index, stack) end
  end,
  ["toggle-help"] = function(player) help_view.toggle(player) end,
  ["close-help"] = function(player) help_view.close(player) end,
  -- A [tip] link opens Tips and Tricks only from chat.
  ["help-tip"] = function(player, tags) player.print({ "seb-message.tip-link", "[tip=" .. tags.tip .. "]" }) end,
  -- The window stays open: the map takes clicks beside it, and its projects
  -- list shows each new project as it starts.
  grow = function(player) tool.give(player) end,
  ["area-tool"] = function(player) tool.give_area(player) end,
  -- Left click: where the project grows now. Right click: all of it.
  ["locate-project"] = function(player, tags, _, event)
    local project = registry.project(tags.project)
    if not (project and project.force_index == player.force.index) then return window.refresh(player) end
    local whole = event.button == defines.mouse_button_type.right
    local found = window.keep_open(player, function() return locate.project(player, project, whole) end)
    if not found then return cursor.say(player, { "seb-message.nothing-to-locate" }) end
    outlines.draw(player, project, LOCATE_OUTLINE_TICKS)
  end,
  ["pause-project"] = with_project(projects.pause),
  ["resume-project"] = with_project(projects.resume),
  ["stop-project"] = with_project(projects.stop),
  ["retry-project"] = with_project(projects.retry),
  ["build-project"] = with_project(projects.build),
  ["list-copies"] = with_project(function(project, player) copies_view.open(player, project) end),
  ["close-copies"] = function(player) copies_view.close(player) end,
  ["locate-copy"] = with_copy(function(instance, player)
    window.keep_open(player, function() return locate.instance(player, instance) end)
  end),
  -- One copy is one piece of work charged to the team (update.cost): it
  -- waits while the team's share of server time is used up.
  ["update-copy"] = with_copy(function(instance, player)
    if not budget.ready(player.force.index) then return cursor.say(player, { "seb-reason.busy" }) end
    local ok, why = update.run(instance)
    if not ok then cursor.say(player, { "seb-reason." .. why }) end
    copies_view.refresh(player)
  end),
  ["remove-copy"] = with_copy(function(instance, player)
    instances.retire(instance)
    copies_view.refresh(player)
  end),
  ["update-project"] = with_project(projects.update_copies),
}

local function route(event, handlers)
  local element = event.element
  if not (element and element.valid) then return end
  local action = element.tags and element.tags.seb
  local handler = action and handlers[action]
  if not handler then return end
  local player = game.get_player(event.player_index)
  if player then handler(player, element.tags, element, event) end
end

function actions.on_click(event)
  route(event, click)
end

local checked = {
  ["grow-direction"] = function(player, tags, element)
    registry.grow_options(player.index).directions[tags.direction] = element.state or nil
  end,
  ["grow-materials"] = function(player, _, element)
    registry.grow_options(player.index).materials = element.state
  end,
  ["grow-retire-depleted"] = function(player, _, element)
    registry.grow_options(player.index).retire_depleted = element.state
  end,
  -- A plan counts its copies in a field of its own: the section swaps it.
  ["grow-dry-run"] = function(player, _, element)
    registry.grow_options(player.index).dry_run = element.state
    window.refresh_grow(player)
  end,
  ["grow-world-directions"] = function(player, _, element)
    registry.grow_options(player.index).world_directions = element.state
  end,
  ["grow-superforce"] = function(player, _, element)
    registry.grow_options(player.index).superforce = element.state
  end,
  ["grow-fast"] = function(player, _, element)
    registry.grow_options(player.index).fast = element.state
  end,
}

function actions.on_checked(event)
  route(event, checked)
end

local text = {
  ["grow-count"] = function(player, _, element)
    local n = tonumber(element.text)
    -- Cleared, it means no count at all, not the default again.
    registry.grow_options(player.index).max_instances = (n and n > 0) and math.floor(n) or false
  end,
  ["grow-plan-count"] = function(player, _, element)
    local n = tonumber(element.text)
    registry.grow_options(player.index).plan_count = (n and n > 0) and math.floor(n) or nil
  end,
  ["grow-preview-ghosts"] = function(player, _, element)
    local n = tonumber(element.text)
    registry.grow_options(player.index).preview_ghosts = (n and n > 0) and math.min(previews.MAX, math.floor(n)) or nil
  end,
}

local chosen = {
  -- The research that moves this design's copies to its newest version.
  ["upgrade-on"] = function(player, tags, element)
    local design = library.get(player.force.index, tags.design)
    if design then research.set(design, element.elem_value) end
  end,
}

function actions.on_elem_changed(event)
  route(event, chosen)
end

function actions.on_text_changed(event)
  route(event, text)
end

local hover = {
  -- Fresh "2 min ago" times each time the pointer comes to a project's text,
  -- and its copies outlined on the map while it stays there.
  ["project-info"] = function(player, tags, element)
    local project = registry.project(tags.project)
    if not (project and project.force_index == player.force.index) then return end
    projects_view.retooltip(element.parent, project)
    outlines.hover(player, project)
  end,
  -- A picture of the design beside the window while the pointer is on it.
  ["select-design"] = function(player, tags)
    local design = library.get(player.force.index, tags.design)
    local frame = window.frame_of(player)
    if design and frame then preview.show(player, frame, design) end
  end,
}

function actions.on_hover(event)
  route(event, hover)
end

-- Enter in the design's name renames it, everywhere it shows.
local confirmed = {
  ["rename-design"] = function(player, tags, element)
    local design = library.get(player.force.index, tags.design)
    if not design then return end
    local old = design.name
    local renamed, why = naming.rename(design, element.text)
    if not renamed then
      element.text = design.name
      return cursor.say(player, { "seb-message." .. why })
    end
    if renamed.name ~= old then player.print({ "seb-message.renamed", old, renamed.name }) end
    window.refresh_force(player.force.index)
  end,
}

function actions.on_confirmed(event)
  route(event, confirmed)
end

local leave = {
  ["select-design"] = function(player) preview.hide(player) end,
  ["project-info"] = function(player) outlines.unhover(player) end,
}

function actions.on_leave(event)
  route(event, leave)
end

-- The name is read once: closing the window destroys the element.
function actions.on_closed(event)
  local element = event.element
  if not (element and element.valid) then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  local name = element.name
  if name == window.NAME and not window.kept(player) then window.on_closed(player) end
  if name == copies_view.NAME then copies_view.close(player) end
end

return actions
