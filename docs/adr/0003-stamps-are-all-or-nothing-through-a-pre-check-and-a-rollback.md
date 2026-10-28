# Stamps are all or nothing, through a pre-check and a rollback

A stamp either goes down whole or reports what stopped it and where. Before building, the mod looks for cliffs under the copy's design tiles and Keep clear tiles, checks every design tile against the tile already there, and calls `LuaSurface.can_place_entity` for every entity with its own name, `build_check_type = blueprint_ghost` and `forced = true`. Every check looks under the parts, never at the whole footprint (`scripts/core/under.lua`). Only then does it build in forced mode, which marks trees and rocks for deconstruction. If the build still comes out short, every ghost it made is destroyed.

Spike S1 measured that this pre-check predicts forced mode exactly, including mining drills with no ore under them, while the variant with `name = "entity-ghost"` and `inner_name` mispredicts next to cliffs. Normal build mode is natively all or nothing, but it also refuses trees and rocks, and it cannot say what was in the way.

Supporting choices:

- **Reasons name the obstacle.** Water, cliff, building, no resource under a drill, uncharted, off-grid, joined another instance. The overlay draws the reason at the obstacle's map position.
- **Tiles get their own check.** The API has no tile placement check. A tile is refused when the item that places it has a plain placement condition that the tile already there collides with, which is how concrete over water is caught. Inverted and tile-list conditions are left to the engine.
- **A design's own landfill excuses water.** `build_blueprint` lays tiles first, so an entity standing on the design's own ground tiles is placed over water although `can_place_entity` said no beforehand.
- **Cliffs under parts stop growth, unless the team can blow them up.** Only a cliff under an entity part, a design tile or a Keep clear tile stops a copy; one in an empty gap of the footprint does not (the engine places both parts and never touches it). With cliff explosives researched (`LuaForce.cliff_deconstruction_enabled`) such a cliff is blown up instead: forced mode marks the cliffs entity ghosts collide with, the stamp orders the ones under tiles (tiles collide with no cliff), the materials gate waits for one explosive per cliff, and a stamp rolled back takes the marks back. A plan treats such a spot as fitting.
- **A short stamp is rolled back, not left incomplete.** This settles the open question in DESIGN.md section 5. Trees that forced mode already marked stay marked.
