-- The window's spacing, in one place: a section is a vanilla subheader bar
-- with its caption (and any buttons the section adds to it), then a padded
-- column for its content; groups inside a column are set apart by a thin
-- line with room above and below.

local layout = {}

layout.PAD = 12        -- a section's content from the window's edges
layout.ROW_GAP = 6     -- between the rows of a section
layout.GROUP_GAP = 4   -- above and below a line between groups

-- Adds a section to `parent`; returns its content column (named `name`)
-- and its bar.
function layout.section(parent, caption, name)
  local bar = parent.add { type = "frame", style = "subheader_frame", direction = "horizontal" }
  bar.style.horizontally_stretchable = true
  bar.add { type = "label", style = "subheader_caption_label", caption = caption }
  local body = parent.add { type = "flow", direction = "vertical", name = name }
  body.style.padding = { 8, layout.PAD, layout.PAD, layout.PAD }
  body.style.vertical_spacing = layout.ROW_GAP
  return body, bar
end

-- A thin line between groups of a column.
function layout.divider(parent)
  local line = parent.add { type = "line", direction = "horizontal" }
  line.style.top_margin = layout.GROUP_GAP
  line.style.bottom_margin = layout.GROUP_GAP
end

-- A row of a column: a horizontal flow, its items centred and spaced.
function layout.row(parent, spacing)
  local flow = parent.add { type = "flow", direction = "horizontal" }
  flow.style.vertical_align = "center"
  flow.style.horizontal_spacing = spacing or 8
  return flow
end

return layout
