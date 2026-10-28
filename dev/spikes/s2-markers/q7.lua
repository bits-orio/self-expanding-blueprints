-- Q7 Events and destruction: script_raised_built for marker ghosts with raise_built and no by_player;
-- destroying marker ghosts inside the handler, or right after build_blueprint returns. Band y=110.
local lib = require("lib")
local q = {id = "Q7"}

local Y = 110.5

-- Marker ghosts sit between ordinary entities so later entities are created after the marker.
-- markers_last puts both combinator markers at the end, to see what a trailing hole does to #.
local function stamp_bp(markers_last)
  if markers_last then
    return lib.new_bp({
      {entity_number = 1, name = "wooden-chest", position = {0.5, 0.5}},
      {entity_number = 2, name = "wooden-chest", position = {1.5, 0.5}},
      {entity_number = 3, name = lib.TAG, position = {2.5, 0.5}, direction = lib.E},
      {entity_number = 4, name = "wooden-chest", position = {3.5, 0.5}},
      {entity_number = 5, name = "transport-belt", position = {4.5, 0.5}, direction = lib.E},
      {entity_number = 6, name = lib.SOCKET, position = {5.5, 0.5}, direction = lib.E},
      {entity_number = 7, name = lib.NOWIRE, position = {6.5, 0.5}, direction = lib.E},
    })
  end
  return lib.new_bp({
    {entity_number = 1, name = "wooden-chest", position = {0.5, 0.5}},
    {entity_number = 2, name = lib.SOCKET, position = {1.5, 0.5}, direction = lib.E, player_description = "q7"},
    {entity_number = 3, name = lib.TAG, position = {2.5, 0.5}, direction = lib.E},
    {entity_number = 4, name = "wooden-chest", position = {3.5, 0.5}},
    {entity_number = 5, name = "transport-belt", position = {4.5, 0.5}, direction = lib.E},
    {entity_number = 6, name = lib.NOWIRE, position = {5.5, 0.5}, direction = lib.E},
    {entity_number = 7, name = "wooden-chest", position = {6.5, 0.5}},
  })
end

local function area_names(surface, x)
  local out = {}
  for _, e in ipairs(surface.find_entities_filtered{area = {{x - 1, Y - 2}, {x + 9, Y + 2}}}) do
    out[#out + 1] = e.name == "entity-ghost" and ("ghost/" .. e.ghost_name) or e.name
  end
  table.sort(out)
  return table.concat(out, ",")
end

local function event_summary(events)
  local out = {}
  for _, ev in ipairs(events) do
    out[#out + 1] = (ev.ghost and ("ghost/" .. ev.ghost) or tostring(ev.name)) .. (ev.destroyed_in_handler and "(destroyed)" or "")
  end
  return #events .. ":[" .. table.concat(out, ",") .. "]"
end

-- Walk the returned array by index, not ipairs: it can hold nil holes. Also count what ipairs and
-- pairs would see, since a hole silently ends an ipairs loop.
local function returned_summary(ghosts)
  local valid, invalid, holes, labels = 0, 0, 0, {}
  for i = 1, #ghosts do
    local g = ghosts[i]
    if g == nil then
      holes = holes + 1
      labels[#labels + 1] = i .. ":NIL"
    elseif g.valid then
      valid = valid + 1
      labels[#labels + 1] = i .. ":" .. (g.ghost_name or g.name)
    else
      invalid = invalid + 1
      labels[#labels + 1] = i .. ":INVALID"
    end
  end
  local n_ipairs, n_pairs = 0, 0
  for _ in ipairs(ghosts) do n_ipairs = n_ipairs + 1 end
  for _ in pairs(ghosts) do n_pairs = n_pairs + 1 end
  local counts = string.format("valid=%d invalid=%d nil_holes=%d ipairs_sees=%d pairs_sees=%d", valid, invalid, holes, n_ipairs, n_pairs)
  return counts, table.concat(labels, ",")
end

local function run_case(ctx, id, x, opts)
  local s = ctx.surface
  local inv, bp = stamp_bp(opts.markers_last)
  lib.rec_start({destroy_markers = opts.destroy_in_handler})
  local ok, ghosts = lib.try(function()
    return bp.build_blueprint{surface = s, force = "player", position = {x + 3.5, Y}, build_mode = defines.build_mode[opts.mode],
      raise_built = opts.raise_built}
  end)
  local events = lib.rec_stop()
  if not ok then
    lib.log("Q7 " .. id, "build_blueprint ERR " .. ghosts)
    inv.destroy()
    return
  end
  local counts, labels = returned_summary(ghosts)
  lib.log("Q7 " .. id, "events=" .. event_summary(events), "returned_len=" .. #ghosts, counts, "[" .. labels .. "]")
  local destroyed_after = 0
  if opts.destroy_after then
    for i = 1, #ghosts do
      local g = ghosts[i]
      if g and g.valid and g.name == "entity-ghost" and lib.MARKERS[g.ghost_name] then
        g.destroy()
        destroyed_after = destroyed_after + 1
      end
    end
  end
  local left = area_names(s, x)
  lib.log("Q7 " .. id, "destroyed_after=" .. destroyed_after, "left_in_area=" .. left)
  local markers_left = select(2, left:gsub("seb%-spike", ""))
  local others = select(2, left:gsub("ghost/wooden%-chest", "")) + select(2, left:gsub("ghost/transport%-belt", ""))
  lib.verdict("Q7 " .. id, markers_left == 0 and others == 4 and #events == opts.want_events,
    string.format("markers_left=%d other_ghosts=%d events=%d (want 0/4/%d)", markers_left, others, #events, opts.want_events))
  for i = 1, #ghosts do
    local g = ghosts[i]
    if g and g.valid then g.destroy() end
  end
  inv.destroy()
end

function q.run(ctx)
  lib.case("Q7 A", function()
    run_case(ctx, "A_normal_destroy_in_handler", 0, {mode = "normal", raise_built = true, destroy_in_handler = true, want_events = 7})
  end)
  lib.case("Q7 B", function()
    run_case(ctx, "B_normal_destroy_after_return", 12, {mode = "normal", raise_built = true, destroy_after = true, want_events = 7})
  end)
  lib.case("Q7 C", function()
    run_case(ctx, "C_forced_destroy_in_handler", 24, {mode = "forced", raise_built = true, destroy_in_handler = true, want_events = 7})
  end)
  lib.case("Q7 D", function()
    run_case(ctx, "D_no_raise_destroy_after_return", 36, {mode = "normal", raise_built = false, destroy_after = true, want_events = 0})
  end)
  lib.case("Q7 E", function()
    run_case(ctx, "E_markers_last_destroy_in_handler", 48,
      {mode = "normal", raise_built = true, destroy_in_handler = true, markers_last = true, want_events = 7})
  end)
end

return q
