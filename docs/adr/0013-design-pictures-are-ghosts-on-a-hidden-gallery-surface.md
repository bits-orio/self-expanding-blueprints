# Design pictures are ghosts on a hidden gallery surface

The playtest of v0.1 found that designs could not be told apart in the window: a design row showed one icon and a name, and the blueprint itself lived in the player's library, out of sight. The window now shows a picture of each design: a card beside the window while a design is hovered, and the chosen design in the Grow section.

Factorio has no GUI element that draws a blueprint. A camera element draws any surface, so every design is built once on a hidden lab surface, `seb-gallery`, and the window points a camera at it. Each design owns a stretch of the surface's x axis, cleared before each build; the copy is rebuilt when the design gets a new version or prototypes change, and removed with the design.

The copy is the design's stamping copy built as ghosts of the design's own force, not revived into real entities. Real entities were tried first: on a surface without power they draw "not connected" and "no power" warnings over the picture, and switched-off poles stop connecting, so the pictures were cluttered with warning icons. Ghosts draw none, never run, and no robots ever reach the surface, so nothing builds them. A camera shows a force its own ghosts, so each team sees only its own designs' pictures, which is what the per-force libraries want anyway.

Supporting choices:

- **Hover events, not tooltips.** A tooltip cannot hold a camera, so the card opens on `on_gui_hover` and closes on `on_gui_leave`, and never takes clicks. In multiplayer it arrives after a round trip.
- **The gallery is a lab like the calibration surface.** Both are floored with lab tiles, generate nothing else, are always day, are hidden from every force (also forces made later) and are kept out of Land Title Registry's claims (`labs.lua`).
- **Cells are reused.** A deleted design's cell, or one a design outgrew, goes back to a free list and is taken before the strip grows; only the chunks a cell covers are asked for.
