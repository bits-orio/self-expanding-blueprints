# S1 Placement: findings

Factorio 2.1.23 headless, base only. Re-run with `dev/run-spike.sh s1-placement 30`.
Final run: 486 PASS lines, 0 FAIL, 0 Lua errors. All evidence below is quoted from that run (long lines trimmed with `...`).

Notation: `P` = the `position` passed to `build_blueprint`. `d` = build direction (0, 4, 8, 12). `pos` = a blueprint entity's position as read back with `get_blueprint_entities()`. `R_d` = quarter turn: north (x, y), east (-y, x), south (-x, -y), west (y, -x). `t_d` = translation with `ghost.position = t_d + R_d(pos)`. `off(e) = ghost.position - P`. `round(v)` = `floor(v + 0.5)`.

## The placement rule (answers Q1 and Q2 together)

For a blueprint with no absolute snapping:

```
B   = bounds of the blueprint content in blueprint coordinates, built from each entity's
      tile footprint (tile_width x tile_height, swapped when the entity faces east or west)
      and each tile as a 1x1 square
c   = centre of B
g   = 2 if any entity has build_grid_size 2 (rails, train stops, ...), else 1
t_d = g * round((P - R_d(c)) / g)        per axis
ghost.position = t_d + R_d(pos)          for every entity
tile ghost position = t_d + R_d(tile.position + (0.5, 0.5))   (the tile's centre)
ghost.direction = (pos.direction + d) % 16
```

In words: the rotated bounds centre lands on P, and the translation is rounded half-up onto the build grid. Collision boxes do not work as the bounds: that variant failed 324 of 1600 random builds. Blueprint snapping is ignored unless absolute snapping is on (see Q1 e and f).

## Q1 Translation invariance

**Answer.** For every unsnapped design, `off(e)` is identical for all integer P. That covered 14 positions: (0,0), (1,0), (0,1), (1,1), (-1,-1), (2,3), (-3,2), (7,-8), (-12,-5), (33,-17), (100,-37), (-101,64), (2000,-3001) and (-99999,100001), in 4 directions, for designs a, a_shift, b, c, c2, g1 to g4 and q4. A fractional P gives a rigid whole-tile shift of the P = 0 stamp. On each rotated axis, that shift is `floor(P)` when the rotated bounds width is odd and `round(P)` when it is even. Examples: P = 0.5 gives no shift on an odd axis and +1 on an even one; P = -0.5 gives -1 and 0.

```
Q1.int a d=4 PASS P_tested=14 n_ret=4(e4+t0) n_found=4 expected=4 off0=e1:assembling-machine-1=-0.5,-0.5/4;...
Q1.frac a d=0 PASS rotated_tile_size=5x4 model=round/grid1 P->eff: 0.5,0.5->0,1 0.25,0.25->0,0 0.75,0.75->0,1 -0.5,-0.5->-1,0 -0.25,-0.25->-1,0 -0.75,-0.75->-1,-1 ... -1.5,2.5->-2,3 0.125,0.875->0,1
Q1.frac b d=0 PASS rotated_tile_size=6x4 ... 0.5,0.5->1,1 ... -0.5,-0.5->0,0
```

- (a) odd 3x3 plus 1x1 extras, bounds 5x4: invariant. `a_shift` is the same design moved by (100, -37) in blueprint coordinates. Its offsets are identical to (a), because the stamp centres on the bounds, not on the blueprint origin.
- (b) 2x2 accumulators, bounds 6x4: invariant. (c) 5x2 with a splitter, and (c2) boiler, pump and steam engine, 6x5: invariant.
- (d) Rails: the rule above with g = 2. Off(e) is invariant only for even P. An odd coordinate snaps to the 2-grid, half-up after the centre shift. This holds for straight rails, curved-rail-a (tile 2x4) and rails mixed with 1x1 entities.
  ```
  Q1.rail d1 d=0 PASS ... even_P_invariant=true model_round_grid2=true ... P->eff: 1,0->0,0 2,0->2,0 3,3->2,2 -1,0->-2,0
  Q1.rail d5 d=0 PASS ... P->eff: 1,0->2,0 0,1->0,0 3,3->4,2 -1,0->0,0   (rail + chest: different rounding, still the model)
  ```
- (e) Relative snapping (6x6, 6x4, and 7x3 on the shifted design) has no effect at all: offsets equal the unsnapped design for integer and fractional P. `Q1.int e d=0 PASS ... relative-snap off0=` is identical to design a.
- (f) Absolute snapping does snap P. Grid lines sit at `rel + k*g'`, where `g'` is the grid with axes swapped for east and west and `rel` is applied in world axes. The blueprint origin (not the content bounds) goes to the top-left of the cell containing P, plus a per-direction shift: N (0,0), E (g'x,0), S (g'x,g'y), W (0,g'y). This model (`G.t_abs` in `lib/geom.lua`) passed 36 checks per design and direction, for grids 6x6 rel (2,1), 6x4 rel (2,1) and 6x6 rel (0,0), and for content moved 13 tiles off the origin.
  ```
  Q1.abs f2 d=4 PASS model=t_abs checked=36 t(P=0)=2,-5 Px->t.x: -6:-2 ... -2:2 ... 1:2 2:6 ... 6:10
  Q1.abs f3 d=0 PASS model=t_abs checked=36 t(P=0)=-4,-3   (same t as f2: content position is irrelevant)
  ```
- (g) Tile ghosts follow the same rigid transform, and tiles count toward the bounds (g2's chest outside the tiles changes t). The returned array includes tile ghosts: tile ghosts first, then entity ghosts in blueprint entity order. Tile ghosts are created on lab tiles and on grass alike.
  ```
  Q1.int g1 d=0 PASS ... n_ret=4(e0+t4)
  Q1.order g3 returned_order=t,t,t,t,1     Q1.order c returned_order=1,2,3,4,5
  Q1.tiles.grass g2 d=0 PASS n_ret=5(e1+t4) ... example_tile_ghost=stone-path@-0.5,399.5 same_offsets_as_lab=true
  ```
- `set_blueprint_entities` moves invalid positions by default: an assembler at (0,0) is stored at (0.5,0.5). With `fix_positions=false` they are kept. Always use the positions read back.
- `skip_fog_of_war`: omitted or false always builds. In a running game, true built nothing in an uncharted chunk. During on_init (map creation) it still built there. `Q1.fog tick=20 ... uncharted chunk (0,0) skip_fog_of_war=true n_ret=0 | omitted n_ret=4`

**Implication.** Calibrate at P = (0,0) and translate by integer P: this is exact for grid-1 designs. Grid-2 designs (anything with rails, train stops, rail supports or cargo bays) only translate by even P relative to the calibration. Never pass a fractional P. Stamp an internal copy with snapping cleared.

## Q2 Rigid transform

**Answer.** Yes. For every entity, including even-sized, non-square and rotated ones, `ghost = t_d + R_d(pos)` exactly. That covered all 72 named cases (9 designs x 4 directions x 2 P) and 1600 random builds: 80 random designs, 282 entities from a pool of 32 prototypes (1x1 to 5x5, 1x2, 2x1, 3x2, 3x5), and 67 tiles, at integer and 1/8-fractional P. Simple Recursive Blueprints' transform predicts every integer-P position. Re-derived algebraically, it is `ghost = P + R_d(pos - c) + frac(c_d)` with c the tile-footprint bounds centre. It only applies to integer P, which is the only case SRB uses.

```
Q2.random PASS designs=80 entities=282 tiles=67 builds=1600 rigid_fail=0 ... round_tile_fail=0 srb_fail=0/960 round_coll_fail=324 dir_bad_builds=0 dir_opposite_by_entity=gate=70,steam-engine=70,steam-turbine=110,storage-tank=90
Q2.random.missing_ghosts_by_entity electric-mining-drill=140   (no ore on lab tiles; see Q6)
```

`t_d` at P = (0,0), with tile bounds and centre c (`t_d = round(P - R_d(c))`):

| design | bounds | c | N | E | S | W |
|---|---|---|---|---|---|---|
| a | [-1,-2..4,2] | 1.5,0 | -1,0 | 0,-1 | 2,0 | 0,2 |
| a_shift | [99,-39..104,-35] | 101.5,-37 | -101,37 | -37,-101 | 102,-37 | 37,102 |
| b | [-1,-1..5,3] | 2,1 | -2,-1 | 1,-2 | 2,1 | -1,2 |
| c | [0,0..5,2] | 2.5,1 | -2,-1 | 1,-2 | 3,1 | -1,3 |
| c2 | [0,0..6,5] | 3,2.5 | -3,-2 | 3,-3 | 3,3 | -2,3 |
| g1 (tiles) | [0,0..3,2] | 1.5,1 | -1,-1 | 1,-1 | 2,1 | -1,2 |
| g4 (tiles) | [5,5..7,7] | 6,6 | -6,-6 | 6,-6 | 6,6 | -6,6 |
| q4 | [0,0..6,3] | 3,1.5 | -3,-1 | 2,-3 | 3,2 | -1,3 |

Directions: rotatable entities give exactly `(D + d) % 16`. Non-rotatable entities stay 0. Two-way symmetric entities (steam-engine, steam-turbine, storage-tank, gate, straight-rail) report the opposite value, i.e. the direction modulo 8: `Q2.dir c2 d=4 ... opposite=steam-engine(4+4=8 got 0)`.

**Implication.** A closed form exists and matches calibration. Calibration is still the simpler production path, because it needs no per-prototype footprint knowledge. Keep the closed form as a test oracle. Footprints come from tile_width/tile_height, never collision boxes. Entities that fail to place, such as drills with no ore, still count toward the bounds.

## Q3 Anchor stability

**(i)** A marker strictly inside the bounds changes nothing else. That covered 67 cases: designs a, b, c, c2 and g2 and 30 random designs, with the marker on an entity's tile or on an empty inside tile, in 4 directions at 3 P each. A marker outside the bounds enlarges them and shifts everything by up to one tile in some directions.
```
Q3.anchor a on-entity@0.5,0.5 PASS ... others_unchanged=true
Q3.anchor a outside@4.5,-1.5 PASS ... others_unchanged=false d0@0,0:shift=-1,0 ... d4@0,0:shift=0,-1
Q3.anchor.summary PASS inside_cases=67 changed=0
```
**(ii)** Clearing snapping (`blueprint_snap_to_grid = nil`, absolute false) leaves the stored positions untouched. The cleared stack then stamps exactly like the never-snapped design. For a relatively snapped blueprint the delta before and after clearing is always (0,0). For an absolutely snapped one, the delta depends on P, because the grid snap goes away.
```
Q3.snapclear e PASS snapped_vs_unsnapped: d0@0,0:delta=0,0 ... stored_positions_unchanged=true cleared_equals_unsnapped=true
Q3.snapclear f PASS snapped_vs_unsnapped: d0@0,0:delta=-3,-5 d0@5,-3:delta=-2,-2 ... cleared_equals_unsnapped=true
```
**Implication.** Calibrate and stamp the same blueprint, markers included: a marker drawn outside the design's footprint moves everything. If the mod ever stamps a copy with markers stripped, it must calibrate that copy. Clearing snapping on the internal copy is safe. The grid size can be kept as data.

## Q4 Marker direction

**Answer.** Yes. With the candidate marker (a constant-combinator copy with an empty collision mask and a hidden only-in-cursor item), the ghost direction is `(D + d) % 16`. The ghost position follows the stamp's rigid transform, and the marker is in the returned array. 48 of 48 passed: D in {0,4,8,12} x d in {0,4,8,12} x 3 P.
```
Q4 d=0 P=3,-5 D=12 PASS ghost_dir=12 expect=12 pos=3.5,-4.5 pos_pred=3.5,-4.5 in_returned_array=true stamp_rigid=true
Q4.summary PASS
```

## Q5 Overlap

**Answer.** A marker ghost is created in normal, forced and superforced mode on top of: a real assembler, a chest or a constant combinator of the same force; chests of the enemy force and of another force; ghosts of an assembler or a chest; a marker ghost facing a different way; trees, rocks and items on the ground; water; and cliffs. It is always in the returned array and never marks anything for deconstruction. A blueprint whose own entities overlap the marker (on an assembler, on a chest, or two markers on one tile) creates all of them. There are two exceptions. An identical marker ghost (same direction) already at that spot means no new ghost and nothing returned. A real marker entity at that spot does the same.
```
Q5 real-own-assembler mode=normal new_marker_ghosts=1 n_ret=1 marker_in_returned=true ... obstacle=valid,decon=false decon_marks=
Q5 water mode=forced new_marker_ghosts=1 n_ret=1 marker_in_returned=true
Q5 marker-ghost-same-dir mode=forced new_marker_ghosts=0 n_ret=0 marker_in_returned=false preexisting_marker_ghosts=1->alive 1
Q5 marker-ghost-other-dir mode=forced new_marker_ghosts=1 n_ret=1 ... marker_dirs_at_W=0,4
Q5 real-marker mode=forced new_marker_ghosts=0 n_ret=0
Q5.inbp mm mode=normal PASS ... ghosts=seb-spike-marker/4@-0.5,0.5;seb-spike-marker/0@-0.5,0.5;wooden-chest/0@1.5,0.5
```
**Implication.** Socket and entry markers can sit anywhere, including over water and other buildings. Read them from the returned array and destroy them in the same tick, so a leftover marker ghost never hides the next stamp's marker. A marker must never become a real entity.

## Q6 Obstacles and build modes

The design was (a) plus a marker on the assembler's centre tile, with the obstacle under the assembler. Bits are in the order assembler, pole, pole, inserter, marker.

| obstacle | normal | forced | superforced |
|---|---|---|---|
| none | all 5 | all 5 | all 5 |
| tree, big-rock | nothing | all 5, tree/rock marked for deconstruction | same as forced |
| water tile | nothing | 4 (no assembler), no landfill ghost | same as forced |
| own-force chest | nothing | 4, chest untouched | all 5, chest marked for deconstruction |
| other-force / enemy / neutral chest | nothing | 4 | 4, nothing marked |
| own-force ghost | nothing | 4, old ghost kept | all 5, old ghost removed |
| item-on-ground | all 5 | all 5 | all 5 (item neither blocks nor gets marked) |
| cliff, no cliff explosives | nothing | 3 (assembler, inserter blocked) | same as forced |
| cliff, cliff-explosives researched | nothing | all 5, cliff marked for deconstruction | same as forced |

Normal mode is all-or-nothing. It refuses trees and rocks, too.

**Pre-check.** `can_place_entity{name = <entity>, position, direction, force, build_check_type = blueprint_ghost, forced = true}` per entity predicted forced mode exactly in every case, including mining drills: no ghost without ore, a ghost with ore. The variant `name = "entity-ghost", inner_name = <entity>` mispredicted near the cliff (01001 against the actual 01101), so do not use it.
```
Q6 tree mode=forced PASS rule=cp_forced==built n_ret=5 built=11111 cp_forced=11111 cp_normal=01111 ... decon=tree-01
Q6 own-building mode=superforced ... built=11111 ... decon=wooden-chest
Q6 cliff mode=superforced ... built=01101 cp_forced=01101 ... cp_ghost_forced=01001
Q6.drill ore=false PASS n_ret=0 cp_forced=false      Q6.drill ore=true PASS n_ret=1 cp_forced=true
```
**Tile caveats.** There is no tile placement check in the API.
- Stone-path tiles over water are silently dropped in every mode. Forced built nothing for a stone-path design with its chest also over water.
- A design's own landfill under an entity makes that entity buildable over water, in every mode, although `can_place_entity` for that entity said false beforehand.
```
Q6.tiles stone-on-water mode=forced n_ret=0 tile_ghosts=0/4 entity_ghosts=0/1
Q6.tiles landfill+chest-on-water mode=normal n_ret=10 tile_ghosts=9/9 entity_ghosts=1/1 ... cp_forced_chest_before=false
```
**Implication.** All-or-nothing stamping works as designed: pre-check every entity with `forced = true` and name the first failure (water, cliff, building of force X, no ore), then stamp forced. Tiles need their own check (water and same-tile) using `get_tile` and tile collision masks. Entities standing on the design's own landfill or foundation must skip the water part of the check. Superforced is only useful for replacing the player's own buildings and ghosts.

## Q7 Calibration surface

**Answer.** A surface made by `game.create_surface` with `generate_with_lab_tiles = true`, with radius-2 chunks generated, had 0 entities and lab tiles. Stamping all 17 designs (12 plain plus 5 rail) in 4 directions at (0,0) gave offsets equal to nauvis in 68 of 68 cases, for force player and for another force. With `raise_built = false`, none of the watched events fired: script_raised_built, on_built_entity, on_marked_for_deconstruction, script_raised_destroy, on_pre_ghost_deconstructed, on_entity_died, on_object_destroyed and others. That held during on_init and in a running game (ticks 5 to 12). Destroying the ghosts left 0 entities. Positive controls: the one ghost registered with `register_on_object_destroyed` did raise on_object_destroyed. In a running game, `raise_built = true` raised `script_raised_built` once per ghost, tile ghosts included.
```
Q7.surface seb-spike-calibration index=2 ... generated_chunks=121 entities=0 tile(0,0)=lab-dark-1
Q7.offsets raise_built=false PASS equal_to_nauvis=68/68 events_during=none
Q7.offsets force=seb-other PASS equal_to_nauvis_player=68/68
Q7.leftovers PASS entities_after_destroy=0 ghosts=0
Q7.tick calibration in a running game PASS equal_to_nauvis=68/68 events_ticks_5_to_12=on_object_destroyed=1 (... positive control) entities_left=0
Q7.control tick=15 g2 PASS raise_built=true n_ret=5(e1+t4) events=script_raised_built=5 | raise_built=false n_ret=5 events=none
Q7.ungenerated chunk_generated_before=false call_ok=true n_ret=0 chunk_generated_after=false
```
Stamping into an ungenerated chunk is silent: no ghosts, no error, no generation. During on_init, even `raise_built = true` delivered no script_raised_built to the mod's own handler; only the tick run shows it.

End to end, the way the mod will place a child: for 40 random designs with an entry marker (inside or just outside the bounds, random D), calibrate `off_d(entry)` on the hidden surface, pick 5 random target tiles W, and stamp on nauvis at `P = W - off_d(entry)` in each direction. The entry ghost landed on W with the calibrated direction 800 of 800 times. For rail designs it hit 40 of 40 when P was even and 0 of 120 when either coordinate was odd.
```
Q7.place grid-1 designs PASS designs=40 stamps=800 entry_on_target=800 non_integer_P=0
Q7.place rail designs PASS P_even: entry_on_target=40/40 P_odd: entry_on_target=0/120
```
**Implication.** The calibration plan is sound. Before calibrating, generate chunks that cover the design's bounds on the hidden surface. For grid-2 designs, require an even P: otherwise close the socket as "off the rail grid", or accept the snapped placement knowingly. After every real stamp, assert that the entry ghost sits on W. That check is free, because marker ghosts are read anyway.

## Q8 Cost (S5-lite)

The design was 100 solar panels plus 25 medium poles (125 entities, 39x39), forced mode, timed with `helpers.create_profiler`, 200 iterations, one machine:

| operation | per call |
|---|---|
| build_blueprint, raise_built=true, running game with a counting handler (25,000 events) | 0.211 ms |
| build_blueprint, raise_built=false, running game | 0.196 ms |
| build_blueprint, on_init, nauvis / calibration surface | 0.19 to 0.24 ms |
| destroy the 125 returned ghosts | 0.046 to 0.049 ms |
| can_place_entity pre-check of all 125 entities | 0.178 ms |
| count_entities_filtered ghost recount over the footprint | 0.004 ms |
| calibration in 4 directions, design a (4 entities) | 0.053 ms |
| calibration in 4 directions, solar design (125 entities) | 1.31 ms |
```
Q8 tick-phase build_blueprint raise_built=true with counting handler per_call Duration: 0.210728ms
Q8 can_place_entity pre-check of all entities per_call Duration: 0.178435ms
Q8 calibration of solar design in 4 directions per_call Duration: 1.306047ms
```
**Implication.** About 1.5 us per entity to stamp and about 1.4 us per entity to pre-check. A 125-entity stamp with its pre-check costs about 0.4 ms. Calibration once per design version is negligible. S5 should still measure many stamps at once, and robots and the recount on real footprints.

## Not tested here

- Anything that needs a real player: `by_player` and `on_built_entity`, `build_from_cursor`, the GUI's own relative-snap cursor placement, undo, and flips (`build_blueprint` has no flip parameter, so flips need a rewritten blueprint).
- Space platforms (foundation tiles, the hub's grid of 256) and Space Age entities with grid 2 (rail ramps, rail supports, cargo bays). Only base rails were tested.
- Mirrored blueprint entities (`mirror = true`), off-grid entities, vehicles, quality, and item requests during calibration.
- True fog of war (charted but not visible): the `chart()` request had not completed by tick 20.
- Robots acting on the stamps. Not needed for S1.
