-- The words for a construction network a project waits on (gates.lua's
-- network_label), shared by the projects list and the map's waiting arrow.

local network_words = {}

-- {personal = name} or {ids = {...}} as a localised string, or nil.
function network_words.of(label)
  if not label then return nil end
  -- A single-player game's player has no name.
  if label.personal == "" or label.personal == "?" then return { "seb-network.personal-unnamed" } end
  if label.personal then return { "seb-network.personal", label.personal } end
  local ids = {}
  for i, id in ipairs(label.ids or {}) do ids[i] = "#" .. id end
  if #ids == 0 then return nil end
  return { "seb-network.fixed", table.concat(ids, ", "), #ids }
end

-- A short key telling two labels apart, for redrawing only on a change.
function network_words.key(label)
  if not label then return "" end
  if label.personal then return "p:" .. label.personal end
  return "n:" .. table.concat(label.ids or {}, ",")
end

-- `text` (a reason's words) followed by the network, when there is one.
function network_words.with(text, label)
  local words = network_words.of(label)
  if not words then return text end
  return { "seb-network.waiting-on", text, words }
end

return network_words
