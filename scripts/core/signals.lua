-- Reading the signals set in a marker. Markers are constant combinators, so
-- a blueprint stores their signals natively as
--   control_behavior.sections.sections[i].filters[j] = {type, name, count, ...}
-- Sections that belong to a logistic group are skipped: a group's contents
-- live in the player's game, not in the blueprint (spike S2).

local signals = {}

local function sections_of(entity)
  local behavior = entity.control_behavior
  local holder = behavior and behavior.sections
  return holder and holder.sections or {}
end

-- The value of the virtual signal `name` set in a blueprint entity (summed
-- over its sections), or nil when it is not set.
function signals.virtual(entity, name)
  local total
  for _, section in ipairs(sections_of(entity)) do
    if not section.group or section.group == "" then
      for _, filter in ipairs(section.filters or {}) do
        if filter.name == name and (filter.type or "item") == "virtual" then total = (total or 0) + (filter.count or 0) end
      end
    end
  end
  return total
end

-- Every non-virtual signal set in a blueprint entity, as {type, name}.
function signals.named(entity)
  local list = {}
  for _, section in ipairs(sections_of(entity)) do
    if not section.group or section.group == "" then
      for _, filter in ipairs(section.filters or {}) do
        local kind = filter.type or "item"
        if filter.name and kind ~= "virtual" then list[#list + 1] = { type = kind, name = filter.name } end
      end
    end
  end
  return list
end

return signals
