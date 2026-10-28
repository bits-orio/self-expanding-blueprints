-- A project's copies that need a look (DESIGN.md "the project window lists
-- projects and instances ... and offers retire, update to the latest
-- version, and show on map"): copies still building, stalled, incomplete,
-- waiting for their ore, or of an older version, each with locate, update
-- and remove. Opened from the project's row; drawn once, and again after
-- each of its own actions.

local const = require("scripts.const")
local update = require("scripts.core.update")
local update_queue = require("scripts.core.update_queue")
local library = require("scripts.core.library")

local copies_view = {}

local NAME = "seb-copies"
copies_view.NAME = NAME
local MAX_ROWS = 40
local STATE = const.STATE

local function close(player)
  local frame = player.gui.screen[NAME]
  if frame then frame.destroy() end
end
copies_view.close = close

-- Why a copy is listed, or nil for one that is simply done.
local function concern(instance)
  if instance.state == STATE.retired then return nil end
  if instance.state == STATE.stalled then return { "seb-copies.stalled", { "seb-reason." .. (instance.reason or "no-progress") } } end
  if instance.state == STATE.incomplete then return { "seb-copies.incomplete" } end
  if instance.state == STATE.building then return { "seb-copies.building", instance.ghosts_left or "?" } end
  if instance.state == STATE.retiring then return { "seb-copies.retiring" } end
  if instance.waiting_ore then return { "seb-copies.waiting-ore" } end
  if not update.outdated(instance) then return nil end
  if update_queue.queued(instance) then return { "seb-copies.update-queued", instance.version } end
  return { "seb-copies.outdated", instance.version }
end

-- An outdated copy not already waiting in its team's line of updates.
local function updatable(instance)
  return update.outdated(instance) and not update_queue.queued(instance)
end

local function listed(project)
  local list = {}
  for id in pairs(project.instance_ids) do
    local instance = storage.instances[id]
    local why = instance and concern(instance)
    if why then list[#list + 1] = { instance = instance, why = why } end
  end
  table.sort(list, function(a, b) return a.instance.id < b.instance.id end)
  return list
end

local function tool(flow, sprite, tooltip, action, instance, style)
  flow.add {
    type = "sprite-button", style = style or "tool_button", sprite = sprite, tooltip = { tooltip },
    tags = { seb = action, instance = instance.id },
  }
end

local function add_row(grid, entry)
  local instance = entry.instance
  local label = grid.add { type = "label", caption = { "", { "seb-copies.copy", instance.id }, " · ", entry.why } }
  label.style.width = 300
  local buttons = grid.add { type = "flow", direction = "horizontal" }
  tool(buttons, "utility/center", "seb-copies.locate", "locate-copy", instance)
  if updatable(instance) then tool(buttons, "utility/refresh", "seb-copies.update", "update-copy", instance) end
  tool(buttons, "utility/trash", "seb-copies.remove", "remove-copy", instance, "tool_button_red")
end

function copies_view.open(player, project)
  close(player)
  local design = library.get(project.force_index, project.design_id)
  local frame = player.gui.screen.add {
    type = "frame", name = NAME, direction = "vertical",
    caption = { "seb-copies.title", project.id, design and design.name or "?" }, tags = { project = project.id },
  }
  frame.auto_center = true
  local body = frame.add { type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" }
  local list = listed(project)
  if #list == 0 then
    body.add { type = "label", caption = { "seb-copies.all-fine", project.count } }
  else
    local scroll = body.add { type = "scroll-pane", style = "naked_scroll_pane", horizontal_scroll_policy = "never" }
    scroll.style.maximal_height = 400
    local grid = scroll.add { type = "table", column_count = 2 }
    for i = 1, math.min(#list, MAX_ROWS) do add_row(grid, list[i]) end
    if #list > MAX_ROWS then body.add { type = "label", caption = { "seb-copies.more", #list - MAX_ROWS } } end
  end
  -- Not player.opened: that would close the main window it was opened from.
  local close_button = body.add { type = "button", caption = { "seb-gui.close" }, tags = { seb = "close-copies" } }
  close_button.style.horizontally_stretchable = true
end

-- After one of its own actions: drawn again for the same project.
function copies_view.refresh(player)
  local frame = player.gui.screen[NAME]
  local project = frame and storage.projects[frame.tags.project]
  if project then copies_view.open(player, project) else close(player) end
end

return copies_view
