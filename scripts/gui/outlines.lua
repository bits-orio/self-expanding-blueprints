-- Outlines of a project's copies on the map, drawn for one player: while
-- the pointer is on the project's row, and for a while after its locate
-- button. A big project shows its first copies only. And while the player
-- holds a design from Grow or the area tool, every copy of their team
-- around them, so a paste over copies already there is no surprise.

local const = require("scripts.const")
local footprints = require("scripts.core.footprints")
local instances = require("scripts.core.instances")
local library = require("scripts.core.library")
local twins = require("scripts.core.twins")

local outlines = {}

local STATE = const.STATE

local MAX = 300           -- copies outlined at most
local HOVER_TICKS = 3600  -- a hover's outlines go by themselves if no leave event comes
local COLOR = { r = 1, g = 0.8, b = 0.1, a = 0.9 }
local AROUND = 160          -- tiles looked over each way from the player
local MAX_AROUND = 500      -- copies outlined around them at most
local COPY_COLOR = { r = 0.55, g = 0.8, b = 1, a = 0.5 }
local EMPTY_COLOR = { r = 1, g = 0.25, b = 0.2, a = 0.9 }
local FLASH = 50            -- copies flashed at most
local FLASH_TICKS = 300
local FLASH_COLOR = { r = 1, g = 0.5, b = 0, a = 1 }
local LABEL_COLOR = { r = 1, g = 0.92, b = 0.85 }
-- A label's text is sized in tiles (it shrinks with the map) and fitted
-- inside its copy: at scale 1 a character is about CHAR tiles wide and a
-- line LINE tiles high (measured on screenshots).
local CHAR, LINE, MAX_SCALE = 0.25, 0.5, 2.5

local function hovered()
  storage.hover_outlines = storage.hover_outlines or {}
  return storage.hover_outlines
end

-- The footprints of the project's copies: stamped ones, then planned ones.
local function boxes(project)
  local list = {}
  for id in pairs(project.instance_ids) do
    if #list >= MAX then return list end
    local instance = storage.instances[id]
    if instance then list[#list + 1] = instance.footprint end
  end
  for _, copy in pairs(project.planned or {}) do
    if #list >= MAX then return list end
    list[#list + 1] = copy.footprint
  end
  return list
end

-- Draws the outlines for `ticks`; returns their render objects.
function outlines.draw(player, project, ticks)
  local surface = game.get_surface(project.surface_index)
  if not surface then return {} end
  local objects = {}
  for _, box in ipairs(boxes(project)) do
    objects[#objects + 1] = rendering.draw_rectangle {
      color = COLOR, width = 2, filled = false, surface = surface, players = { player },
      left_top = { box.left, box.top }, right_bottom = { box.right, box.bottom }, time_to_live = ticks,
    }
  end
  return objects
end

local function destroy(list)
  for _, object in ipairs(list or {}) do
    if object.valid then object.destroy() end
  end
end

function outlines.unhover(player)
  local list = hovered()[player.index]
  hovered()[player.index] = nil
  destroy(list)
end

function outlines.hover(player, project)
  outlines.unhover(player)
  hovered()[player.index] = outlines.draw(player, project, HOVER_TICKS)
end

local function around()
  storage.cursor_outlines = storage.cursor_outlines or {}
  return storage.cursor_outlines
end

-- A copy built to the end whose buildings were all removed by hand: it
-- still holds its place, until a right-drag with the area tool retires it.
local function emptied(instance)
  local state = instance.state
  return (state == STATE.complete or state == STATE.incomplete)
    and #instance.prepared.placements > 0 and instances.built_entities(instance) == 0
end

local function holds_tool(player)
  local stack = player.cursor_stack
  return stack and stack.valid_for_read and (stack.name == const.GROW_BLUEPRINT or stack.name == const.TOOL)
end

-- What a copy is called on the map: its project and design as the
-- project's row names them ("#2 Solar cell"), the design alone once the
-- project is gone.
function outlines.label(instance)
  local design = library.get(instance.force_index, instance.design_id)
  local name = design and twins.origin(design).name or "?"
  local project = storage.projects[instance.project_id or 0]
  if project then return { "seb-gui.project-name", project.id, name } end
  return name
end

-- The scale that fits two lines of at most `chars` characters in the box.
local function fitted(box, chars)
  local width, height = box.right - box.left, box.bottom - box.top
  return math.min(MAX_SCALE, 0.9 * width / (CHAR * chars), 0.9 * height / (2 * LINE))
end

-- The copy's design and, below it, its project, centred on the copy, for
-- `ticks` (nil: until destroyed). Returns the render objects.
local function draw_label(player, surface, instance, ticks)
  local b = instance.footprint
  local design = library.get(instance.force_index, instance.design_id)
  local name = design and twins.origin(design).name or "?"
  local project = storage.projects[instance.project_id or 0]
  local args = {
    surface = surface, players = { player }, color = LABEL_COLOR, alignment = "center", time_to_live = ticks,
    target = { (b.left + b.right) / 2, (b.top + b.bottom) / 2 }, scale = fitted(b, math.max(#name, 10)),
  }
  local function line(text, vertical)
    args.text, args.vertical_alignment = text, vertical
    return rendering.draw_text(args)
  end
  if not project then return { line(name, "middle") } end
  return { line(name, "bottom"), line({ "seb-gui.copy-project", project.id }, "top") }
end

-- The team's copies around the player (where they look, in remote view
-- too), emptied ones in red and named.
local function draw_around(player)
  local surface, force_index, at = player.surface, player.force.index, player.position
  local box = { left = at.x - AROUND, top = at.y - AROUND, right = at.x + AROUND, bottom = at.y + AROUND }
  local objects = {}
  for _, id in ipairs(footprints.overlapping(surface.index, box)) do
    if #objects >= MAX_AROUND then break end
    local instance = storage.instances[id]
    if instance and instance.force_index == force_index then
      local empty, b = emptied(instance), instance.footprint
      objects[#objects + 1] = rendering.draw_rectangle {
        color = empty and EMPTY_COLOR or COPY_COLOR, width = empty and 2 or 1, filled = false, surface = surface,
        players = { player }, left_top = { b.left, b.top }, right_bottom = { b.right, b.bottom },
      }
      if empty then
        for _, object in ipairs(draw_label(player, surface, instance)) do objects[#objects + 1] = object end
      end
    end
  end
  return objects
end

-- The copies `ids` highlighted for a few seconds, each named.
function outlines.flash(player, ids)
  for i = 1, math.min(#ids, FLASH) do
    local instance = storage.instances[ids[i]]
    local surface = instance and game.get_surface(instance.surface_index)
    if surface then
      local b = instance.footprint
      rendering.draw_rectangle {
        color = FLASH_COLOR, width = 3, filled = false, surface = surface, players = { player },
        left_top = { b.left, b.top }, right_bottom = { b.right, b.bottom }, time_to_live = FLASH_TICKS,
      }
      draw_label(player, surface, instance, FLASH_TICKS)
    end
  end
end

-- The player's cursor changed, or their tool selected an area: the copies
-- around them while they hold a design from Grow or the area tool.
function outlines.cursor_changed(player)
  destroy(around()[player.index])
  around()[player.index] = holds_tool(player) and draw_around(player) or nil
end

return outlines
