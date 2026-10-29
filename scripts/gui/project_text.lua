-- Words for a project's status and history (core/status.lua,
-- core/history.lua), as localised strings for the projects list: the status
-- light, the lines of a row and the history tooltip. Times in the tooltip are
-- relative to when it is drawn, so the row redraws it on hover.

local const = require("scripts.const")
local frontier = require("scripts.core.frontier")
local network_words = require("scripts.network_words")

local project_text = {}

local REASON = const.REASON

local LIGHT = {
  growing = "utility/status_working", waiting = "utility/status_yellow", stalled = "utility/status_not_working",
  paused = "utility/status_inactive", finished = "utility/status_blue", stopped = "utility/status_inactive",
  planned = "utility/status_blue", planning = "utility/status_blue",
}
local COLOR = {
  growing = "green", waiting = "yellow", stalled = "red", paused = "gray", finished = "acid", stopped = "gray",
  planned = "cyan", planning = "cyan",
}
local HISTORY_LINES = 5

local function item_icon(item)
  if item.quality and item.quality ~= "normal" then
    return "[item=" .. item.name .. ",quality=" .. item.quality .. "]"
  end
  return "[item=" .. item.name .. "]"
end

local function reason(key)
  return { "seb-reason." .. key }
end

-- Why a project that ended without placing a copy did, and where.
local function nothing_built(project)
  local note = project and project.count == 0 and project.nothing_built
  if not (note and note.reason) then return nil end
  local at = note.position or { x = 0, y = 0 }
  local key = project.dry_run and "seb-status.nothing-planned" or "seb-status.nothing-built"
  return { key, reason(note.reason), math.floor(at.x), math.floor(at.y) }
end

-- A project that ended with nothing placed shows as stalled: it went wrong.
function project_text.light(s, project)
  return nothing_built(project) and LIGHT.stalled or LIGHT[s.level]
end

-- What holds it, or nothing for a project that is plainly growing.
function project_text.why(s, project)
  local none = nothing_built(project)
  if none then return none end
  if s.level == "waiting" and s.reason == REASON.missing_materials and s.item then
    return network_words.with({ "seb-status.missing", s.item.count, item_icon(s.item), s.item.have or 0 }, s.network)
  end
  if s.level == "waiting" and s.reason == REASON.no_network then return { "seb-status.unreachable-all", s.count } end
  if s.level == "waiting" and s.reason == REASON.ore_left then return { "seb-status.ore-all", s.count } end
  if s.level == "waiting" then return network_words.with(reason(s.reason), s.network) end
  if s.level == "stalled" and s.reason == REASON.no_progress then return { "seb-status.stalled-quiet", s.count } end
  if s.level == "stalled" then return { "seb-status.stalled-copies", s.count, reason(s.reason) } end
  if s.level == "growing" and s.unreachable > 0 then return { "seb-status.unreachable-some", s.unreachable } end
  if s.level == "growing" and (s.ore or 0) > 0 then return { "seb-status.ore-some", s.ore } end
  if s.level == "finished" and s.reason then return { "seb-status.finished-by", reason(s.reason), s.count } end
  if s.level == "planned" then return { "seb-status.plan-ready", s.count } end
  if s.level == "planning" and s.reason then return reason(s.reason) end
end

-- The row's text: name and coloured state, counts, why, if anything holds
-- it, and whether its copies wait their turn to be updated.
function project_text.caption(project, s, name, updating)
  local color = nothing_built(project) and COLOR.stalled or COLOR[s.level]
  local open = frontier.pending(project)
  local progress = project.dry_run and { "seb-gui.plan-progress", project.count, open }
    or { "seb-gui.project-progress", project.count - project.building, project.building, open }
  local turned = { "seb-gui.project-turned", { project.mirrored and "seb-gui.paste-flipped" or "seb-gui.paste-unflipped" },
    { project.world_directions and "seb-gui.axis-world" or "seb-gui.axis-paste" } }
  local lines = {
    "", "[font=default-bold]", { "seb-gui.project-name", project.id, name }, "[/font]  [color=", color, "]",
    { "seb-status." .. s.level }, "[/color]  [color=150,150,150]", turned, "[/color]\n", progress,
  }
  local why = project_text.why(s, project)
  if why then
    lines[#lines + 1] = { "", "\n[color=", color, "]", why, "[/color]" }
  end
  if updating then lines[#lines + 1] = { "", "\n", { "seb-status.updating" } } end
  return lines
end

local function ago(ticks)
  local seconds = math.floor(ticks / 60)
  if seconds < 5 then return { "seb-time.now" } end
  if seconds < 60 then return { "seb-time.seconds", seconds } end
  if seconds < 3600 then return { "seb-time.minutes", math.floor(seconds / 60) } end
  return { "seb-time.hours", math.floor(seconds / 3600) }
end

local function at(position)
  return position and { "seb-history.at", math.floor(position.x), math.floor(position.y) } or ""
end

local function who(entry)
  local player = entry.player_index and game.get_player(entry.player_index)
  return player and { "seb-history.by", player.name } or ""
end

local WORDS = {
  started = function(e) return { "seb-history.started", at(e.position) } end,
  waiting = function(e)
    if e.reason == REASON.missing_materials and e.item then
      return { "seb-history.waiting-for", e.item_count or "?", "[item=" .. e.item .. "]" }
    end
    return reason(e.reason)
  end,
  blocked = function(e) return { "seb-history.blocked", reason(e.reason), at(e.position) } end,
  unreachable = function(e) return { "seb-history.unreachable", at(e.position) } end,
  stalled = function(e)
    if e.reason == REASON.no_progress then return { "seb-history.stalled-quiet" } end
    return { "seb-history.stalled", reason(e.reason) }
  end,
  incomplete = function() return { "seb-history.incomplete" } end,
  paused = function(e) return { "seb-history.paused", who(e) } end,
  resumed = function(e) return { "seb-history.resumed", who(e) } end,
  finished = function(e) return { "seb-history.finished", e.copies or 0 } end,
  ["waiting-ore"] = function() return { "seb-history.waiting-ore" } end,
  ["ore-gone"] = function() return { "seb-history.ore-gone" } end,
  depleted = function() return { "seb-history.depleted" } end,
  ["built-plan"] = function(e) return { "seb-history.built-plan", who(e) } end,
  replaced = function(e) return { "seb-history.replaced", e.limit or "?" } end,
  retried = function(e) return { "seb-history.retried", e.count or 0, who(e) } end,
  updated = function(e) return { "seb-history.updated", e.copies or 0, e.refused or 0 } end,
}

local function line(entry, now)
  local words = WORDS[entry.kind]
  local text = words and words(entry) or entry.kind
  local times = entry.count > 1 and { "seb-history.times", entry.count } or ""
  return { "seb-history.line", ago(now - entry.tick), text, times }
end

-- Name, state and why, then the newest history lines, newest first.
function project_text.tooltip(project, s, name)
  local out = { "", { "seb-gui.project-name", project.id, name }, " - ", { "seb-status." .. s.level } }
  local why = project_text.why(s, project)
  if why then out[#out + 1] = { "", "\n", why } end
  local list, now = project.history or {}, game.tick
  if #list > 0 then out[#out + 1] = { "", "\n\n", { "seb-history.heading" } } end
  for i = #list, math.max(1, #list - HISTORY_LINES + 1), -1 do
    out[#out + 1] = { "", "\n", line(list[i], now) }
  end
  return out
end

return project_text
