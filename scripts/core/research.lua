-- Research-driven upgrades (DESIGN.md section 5): a design can name a
-- technology; when the design's force finishes that research, every copy of
-- the design moves to its newest version in place (update.lua), a few per
-- run of the due-tick queue (update_queue.lua). Register the better version
-- first, then name the research that unlocks its parts.

local library = require("scripts.core.library")
local update = require("scripts.core.update")
local update_queue = require("scripts.core.update_queue")

local research = {}

-- hooks.updated(force_index, design, done, refused): set by control.lua,
-- called for each design that named the research once its copies are done.
research.hooks = {}

-- Names (or clears, with nil) the technology that upgrades a design's copies.
function research.set(design, technology)
  design.upgrade_on = technology
  local twin = design.twin_id and library.get(design.force_index, design.twin_id)
  if twin then twin.upgrade_on = technology end
end

-- The ids of the force's designs that name the technology, in id order, and
-- the same as a set (design numbers are unique across forces).
local function named(force_index, technology)
  local ids, set = {}, {}
  for _, design in ipairs(library.list(force_index)) do
    if design.upgrade_on == technology then
      -- A mirror twin's copies upgrade with the design's.
      for _, id in ipairs({ design.id, design.twin_id }) do
        ids[#ids + 1] = id
        set[id] = true
      end
    end
  end
  return ids, set
end

-- One pass over every copy, however many designs name the technology: the
-- outdated copies of those designs, oldest first.
local function outdated_of(set)
  local ids = {}
  for id, instance in pairs(storage.instances) do
    if set[instance.design_id] and update.outdated(instance) then ids[#ids + 1] = id end
  end
  table.sort(ids)
  return ids
end

local function report(batch)
  if not research.hooks.updated then return end
  for _, id in ipairs(batch.designs) do
    local design = library.get(batch.force_index, id)
    local tally = batch.by_design[id] or { done = 0, refused = 0 }
    if design then research.hooks.updated(batch.force_index, design, tally.done, tally.refused) end
  end
end
update_queue.done.research = report

function research.on_research_finished(event)
  local tech = event.research
  local force_index = tech.force.index
  local ids, set = named(force_index, tech.name)
  if #ids == 0 then return end
  local batch = { kind = "research", designs = ids }
  if update_queue.add(force_index, outdated_of(set), batch) == 0 then report(batch) end
end

return research
