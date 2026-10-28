-- The blueprint builder's window, shown instead of the decider combinator
-- it is built on: what it is doing, its last answer, and every signal it
-- understands, so a player can wire one up without leaving the game.

local const = require("scripts.const")
local roster = require("scripts.circuit.roster")

local builder_view = {}

local NAME = "seb-builder-window"
builder_view.NAME = NAME

local function verb_signal(verb)
  return "seb-" .. verb
end

-- {heading key, {signals, description key}...} for the reference. A row
-- names one signal or several that work together; a row without a
-- description key is named by its signal alone.
local ERRORS = {
  "water", "cliff", "building", "held-land", "uncharted", "materials", "unknown-design", "out-of-range",
  "not-found", "invalid", "no-resource", "probe", "incomplete", "stopped", "limit",
}

local function error_rows()
  local rows = {}
  for i, name in ipairs(ERRORS) do rows[i] = { "seb-error-" .. name } end
  return rows
end

local REFERENCE = {
  { "builder-verbs", {
    { "seb-stamp", "builder-stamp" }, { "seb-grow", "builder-grow" },
    { "seb-remove", "builder-remove" }, { "seb-clear", "builder-clear" },
    { "seb-sense", "builder-sense" }, { "seb-find", "builder-find" },
    { "seb-capture", "builder-capture" }, { "seb-upgrade", "builder-upgrade" },
    { "seb-read", "builder-read" }, { "seb-write", "builder-write" },
  } },
  { "builder-inputs", {
    { "seb-design", "builder-design" }, { { "signal-X", "signal-Y" }, "builder-xy" },
    { { "signal-W", "signal-H" }, "builder-wh" }, { "signal-R", "builder-rotation" },
    { "seb-absolute", "builder-absolute" }, { "seb-superforce", "builder-superforce" },
    { "seb-instance", "builder-instance" }, { "seb-count", "builder-count" },
    { { "seb-grow-north", "seb-grow-east", "seb-grow-south", "seb-grow-west" }, "builder-sides" },
    { "seb-pause", "builder-pause" }, { "seb-stop", "builder-stop" },
    { { "seb-grid-x", "seb-grid-y", "seb-spacing" }, "builder-grid" },
    { "seb-radius", "builder-radius" }, { "seb-cancel", "builder-cancel" },
  } },
  { "builder-sense-what", {
    { "seb-sense-entities", "builder-sense-entities" }, { "seb-sense-ghosts", "builder-sense-ghosts" },
    { "seb-sense-resources", "builder-sense-resources" }, { "seb-sense-trees", "builder-sense-count" },
    { "seb-sense-water", "builder-sense-count" }, { "seb-sense-enemies", "builder-sense-count" },
  } },
  { "builder-outputs", {
    { "seb-ack", "builder-ack" }, { "seb-done", "builder-done" }, { "seb-error", "builder-error" },
    { "seb-ghosts-left", "builder-ghosts-left" }, { { "seb-open-sockets", "seb-blocked-sockets" }, "builder-sockets" },
    { "seb-built", "builder-built" },
  } },
  { "builder-errors", error_rows() },
}

local function close(player)
  local frame = player.gui.screen[NAME]
  if frame then frame.destroy() end
end
builder_view.close = close

local function state_line(b)
  if b and b.waiting then return { "seb-gui.builder-over-limit", roster.limit(b) } end
  local request = b and b.request
  if not request then return { "seb-gui.builder-idle" } end
  local verb = "[virtual-signal=" .. verb_signal(request.verb) .. "]"
  local key = request.finished and "seb-gui.builder-answered" or "seb-gui.builder-working"
  return { key, verb, request.number }
end

-- A row's signals, each as its icon and name.
local function names_caption(signals)
  if type(signals) == "string" then signals = { signals } end
  local caption = { "" }
  for i, signal in ipairs(signals) do
    if i > 1 then caption[#caption + 1] = "\n" end
    caption[#caption + 1] = "[virtual-signal=" .. signal .. "] "
    caption[#caption + 1] = { "virtual-signal-name." .. signal }
  end
  return caption
end

-- Each signal as its icon and name, then what it does.
local function reference(parent)
  for _, section in ipairs(REFERENCE) do
    parent.add { type = "label", caption = { "seb-gui." .. section[1] }, style = "caption_label" }
    local grid = parent.add { type = "table", column_count = 2 }
    grid.style.vertical_spacing = 2
    for _, row in ipairs(section[2]) do
      local name = grid.add { type = "label", caption = names_caption(row[1]) }
      name.style.font = "default-bold"
      name.style.single_line = false
      local text = grid.add { type = "label", caption = row[2] and { "seb-gui." .. row[2] } or "" }
      text.style.single_line = false
      text.style.maximal_width = 330
    end
  end
end

function builder_view.open(player, entity)
  close(player)
  local b = storage.builders[entity.unit_number]
  local frame = player.gui.screen.add {
    type = "frame", name = NAME, direction = "vertical", caption = { "entity-name." .. const.BUILDER },
  }
  frame.auto_center = true
  local body = frame.add { type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" }
  body.add { type = "label", caption = state_line(b), style = "bold_label" }
  local intro = body.add { type = "label", caption = { "seb-gui.builder-intro" } }
  intro.style.single_line = false
  intro.style.maximal_width = 540
  local scroll = body.add { type = "scroll-pane", style = "naked_scroll_pane", horizontal_scroll_policy = "never" }
  scroll.style.maximal_height = math.max(300, math.floor(player.display_resolution.height / player.display_scale) - 260)
  reference(scroll)
  player.opened = frame
end

return builder_view
