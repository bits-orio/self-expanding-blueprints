-- The projects section: on a design's page one row per project of that
-- design, on the front page those of deleted designs; each with a status
-- light, its state and progress, why it waits or stalled, its history on
-- hover, and locate, pause, resume, retry and stop buttons.
-- Rows are updated in place, never rebuilt while a project grows: in
-- multiplayer a click names its element, and a click on an element destroyed
-- in the meantime is lost. Child names carry a prefix so that none shadows a
-- LuaGuiElement property ("name", "state", "text") when looked up by name.

local const = require("scripts.const")
local library = require("scripts.core.library")
local projects = require("scripts.core.projects")
local registry = require("scripts.core.registry")
local twins = require("scripts.core.twins")
local layout = require("scripts.gui.layout")
local status = require("scripts.core.status")
local frontier = require("scripts.core.frontier")
local update_queue = require("scripts.core.update_queue")
local designs_view = require("scripts.gui.designs_view")
local project_text = require("scripts.gui.project_text")
local retry = require("scripts.core.retry")

local projects_view = {}

local NAME = "seb-projects"

local function shown(project)
  local design = library.get(project.force_index, project.design_id)
  local s = status.of(project)
  -- Copies of an older version than the design's newest can be updated,
  -- unless they already wait their turn.
  local updating = update_queue.waiting(project) > 0
  local outdated = design ~= nil and project.oldest_version ~= nil and project.oldest_version < design.version
    and not updating
  local list = project.history or {}
  local last = list[#list]
  local retries = retry.count(project)
  return {
    icon = designs_view.icon_sprite(design and design.icon), name = design and design.name or "?", status = s,
    outdated = outdated, updating = updating, retries = retries,
    key = table.concat({
      retries,
      tostring(outdated), tostring(updating),
      s.level, s.reason or "", s.count or "", s.unreachable or "", s.item and s.item.name or "",
      s.item and s.item.have or "", project.count, project.building, frontier.pending(project),
      #list, last and last.tick or "", last and last.count or "",
    }, "|"),
  }
end

-- Everything a row shows, as one string: a project whose key has not changed
-- needs no redraw in any window.
function projects_view.key(project)
  local s = shown(project)
  return s.icon .. "|" .. s.name .. "|" .. s.key
end

local function button(flow, name, sprite, style, tooltip, action, project)
  flow.add {
    type = "sprite-button", name = name, style = style, sprite = sprite,
    tooltip = { tooltip }, tags = { seb = action, project = project.id },
  }
end

-- Pause and resume are two buttons shown in turn: flipping one button's
-- action would let a click already in flight do the opposite. A project
-- that can do neither keeps a disabled pause in that slot, so the stop
-- button never slides under a click aimed at pause. The text raises hover
-- events so its history tooltip can be redrawn with fresh times.
local function add_row(rows, project, index)
  local frame = rows.add {
    type = "frame", name = "p" .. project.id, style = "bordered_frame", direction = "horizontal", index = index,
  }
  frame.style.horizontally_stretchable = true
  local row = frame.add { type = "flow", name = "proj_row", direction = "horizontal" }
  row.style.vertical_align = "center"
  row.style.horizontal_spacing = 8
  button(row, "proj_locate", "utility/center", "tool_button", "seb-gui.locate", "locate-project", project)
  row.add {
    type = "sprite", name = "proj_light", raise_hover_events = true, tags = { seb = "project-info", project = project.id },
  }
  row.add { type = "sprite", name = "proj_icon" }
  local info = row.add {
    type = "label", name = "proj_info", raise_hover_events = true,
    tags = { seb = "project-info", project = project.id },
  }
  info.style.single_line = false
  -- Leaves room for the list's scrollbar once it scrolls.
  info.style.width = 290
  local buttons = row.add { type = "flow", name = "proj_buttons", direction = "horizontal" }
  button(buttons, "proj_pause", "utility/pause", "tool_button", "seb-gui.pause", "pause-project", project)
  button(buttons, "proj_resume", "utility/play", "tool_button", "seb-gui.resume", "resume-project", project)
  button(buttons, "proj_build", "utility/check_mark_green", "tool_button_green", "seb-gui.build-plan", "build-project", project)
  button(buttons, "proj_update", "utility/refresh", "tool_button", "seb-gui.update-project", "update-project", project)
  button(buttons, "proj_copies", "utility/list_view", "tool_button", "seb-gui.copies", "list-copies", project)
  button(buttons, "proj_retry", "utility/reset", "tool_button", "seb-gui.retry-project", "retry-project", project)
  button(buttons, "proj_stop", "utility/close", "tool_button_red", "seb-gui.stop", "stop-project", project)
  return frame
end

-- The history tooltip, with times counted from now.
function projects_view.retooltip(row, project)
  local s = shown(project)
  local tooltip = project_text.tooltip(project, s.status, s.name)
  row.proj_info.tooltip = tooltip
  row.proj_light.tooltip = tooltip
end

local function update_row(frame, project)
  local row = frame.proj_row
  local s = shown(project)
  row.proj_light.sprite = project_text.light(s.status, project)
  row.proj_icon.sprite = s.icon
  row.proj_info.caption = project_text.caption(project, s.status, s.name, s.updating)
  projects_view.retooltip(row, project)
  local state = project.state
  local buttons = row.proj_buttons
  local plan_only = project.dry_run == true
  buttons.proj_pause.visible = state ~= const.PROJECT_STATE.paused and not plan_only
  buttons.proj_pause.enabled = state == const.PROJECT_STATE.growing
  buttons.proj_resume.visible = state == const.PROJECT_STATE.paused and not plan_only
  buttons.proj_build.visible = plan_only
  buttons.proj_build.enabled = state == const.PROJECT_STATE.finished
  buttons.proj_update.visible = s.outdated
  -- Retry keeps its slot, disabled with nothing to try, so stop never
  -- slides under a click aimed at it. A row drawn before the button existed
  -- has none until the window redraws.
  local retry_button = buttons.proj_retry
  if retry_button then
    retry_button.enabled = s.retries > 0
    retry_button.tooltip = s.retries > 0 and { "seb-gui.retry-project", s.retries } or { "seb-gui.retry-none" }
  end
end

-- Whether the project belongs in the player's window: on a design's page,
-- a project of that design; on the front page, one whose design is gone.
local function belongs(project, player)
  if project.state == const.PROJECT_STATE.stopped then return false end
  local state = registry.player(player.index)
  -- A flipped project grows a mirror twin, and shows under its design.
  local origin = twins.origin_id(project.force_index, project.design_id)
  if state.design_open then return origin == state.selected_design end
  return library.get(project.force_index, origin) == nil
end

local function listed(player)
  local list = {}
  for _, project in ipairs(projects.list(player.force.index)) do
    if belongs(project, player) then list[#list + 1] = project end
  end
  return list
end

-- The front page shows the section only while a deleted design's project runs.
local function fill(holder, player)
  local list = listed(player)
  if #list == 0 then
    if registry.player(player.index).design_open then
      holder.add { type = "label", name = "proj_none", caption = { "seb-gui.no-projects" } }
    end
    return
  end
  local pane = holder.add {
    type = "scroll-pane", name = "proj_pane", style = "naked_scroll_pane",
    vertical_scroll_policy = "auto", horizontal_scroll_policy = "never",
  }
  local rows = pane.add { type = "flow", name = "proj_rows", direction = "vertical" }
  rows.style.vertical_spacing = layout.ROW_GAP
  for _, project in ipairs(list) do update_row(add_row(rows, project), project) end
end

function projects_view.build(parent, player)
  local open = registry.player(player.index).design_open
  if not open and #listed(player) == 0 then return end
  fill(layout.section(parent, { open and "seb-gui.projects" or "seb-gui.orphan-projects" }, NAME), player)
end

-- Redraws the whole section (a window opened, records dropped).
function projects_view.refresh(body, player)
  local holder = body[NAME]
  if not holder then return end
  holder.clear()
  fill(holder, player)
end

-- Where a new row goes to keep the rows in id order.
local function index_for(rows, id)
  for i, child in ipairs(rows.children) do
    if tonumber(child.name:sub(2)) > id then return i end
  end
end

-- Updates, adds or removes one project's row. Only a list that becomes empty,
-- or stops being empty, is redrawn whole.
function projects_view.refresh_row(body, player, project)
  local holder = body[NAME]
  local rows = holder and holder.proj_pane and holder.proj_pane.proj_rows
  if not rows then return projects_view.refresh(body, player) end
  local row = rows["p" .. project.id]
  if not (storage.projects[project.id] and belongs(project, player)) then
    if row then row.destroy() end
    if #rows.children == 0 then projects_view.refresh(body, player) end
    return
  end
  update_row(row or add_row(rows, project, index_for(rows, project.id)), project)
end

return projects_view
