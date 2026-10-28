# Stamps land by calibrating a stamping copy of the design

Every design keeps two blueprints: the player's blueprint as registered, and a stamping copy with snapping cleared and one anchor entity added inside its bounds. When a design version is registered, the copy is stamped at the origin of a hidden lab surface in each of the four directions, the anchor's ghost is read, and everything is destroyed in the same tick. That gives `offsets[d]`, and every position follows:

```
world(bp, P, d) = P + offsets[d] + rotate(bp, d)
```

Spike S1 established that this is exact (`dev/spikes/s1-placement/FINDINGS.md`): `build_blueprint` places every entity by a rigid transform of its blueprint position, translation invariant for whole-tile build positions, and the calibrate-then-translate plan put an entry arrow on its target 800 times out of 800. A closed form exists (the rotated centre of the tile-footprint bounds lands on P), but calibration needs no per-prototype footprint knowledge and keeps working if the engine's rules change.

Supporting choices:

- **Snapping is cleared on the copy.** Relative snapping is ignored by `build_blueprint` anyway; absolute snapping would snap P to a grid. The grid size is kept as data, for Level 1 growth steps (ADR-0006).
- **The anchor sits inside the bounds.** A marker inside the bounds moves nothing else; one outside shifts the whole stamp by up to a tile. Calibration stamps the copy exactly as it will be stamped, markers included.
- **Rail-grid designs need even positions.** Anything with `build_grid_size` 2 only translates by even steps. Seeds round onto the lattice, implicit steps round up to it, and a socket or entry target that falls off it closes with "off-grid" rather than landing a tile away.
- **Footprints come from tile sizes.** The engine measures a blueprint by `tile_width` and `tile_height` (turned for east and west), not by collision boxes, and so does the mod.
- **The entry is asserted after every stamp.** Marker ghosts are read anyway, so checking that the entry landed on its target and faces the right way is free; a miss rolls the stamp back as "misaligned".
