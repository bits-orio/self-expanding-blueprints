# S3 Tracking coverage: findings

Factorio 2.1.23 headless. Re-run with `dev/run-spike.sh s3-tracking 3600 [space-age]`.

Written by the orchestrating session from the spike agent's structured report (the harness does not let subagents write report files). Evidence lines are quoted from the spike's final run; long lines are trimmed.

## Q1 Tags on each build path (robot, script revive, anything else raised; player)

**Answer** (high confidence). Robots: on_robot_built_entity carries event.tags with seb_instance: 3/3 in case A, 100/100 in case C, and zero untagged robot builds. Script revive: revive{raise_revive=true} and silent_revive{raise_revive=true} both raise script_raised_revive with the tags. Each call raised exactly that one event (no script_raised_built, no on_built_entity), including the assembler revive that created an item-request-proxy. Revive without raise_revive raises nothing. Blueprint-supplied entity tags survive alongside seb_instance when the mod merges into them. With raise_built=true, build_blueprint raises script_raised_built for every entity ghost and every tile ghost during the call, before the mod can tag them: tags_at_raise is nil, or only the blueprint's own tags. Player hand-building is untested (no player headless).

```
t=491 VERDICT Q1 robot_built_carries_tags PASS robot_built=3 tagged=3 ghosts=3
t=796 VERDICT Q1 C_all_robot_builds_tagged PASS built_tagged=100 n_ghosts=100 untagged_events=nil
t=468 BUILT path=robot case=A ent=iron-chest#533 tags={design_tag = "kept", seb_instance = 1}
t=5 s=32 EV script_raised_revive case=S:revive:raise=true entity=wooden-chest#32 tags={seb_instance = 2}
t=5 s=36 EV script_raised_revive case=S:silent_revive:raise=true entity=iron-chest#33 tags={seb_instance = 2}
t=5 s=38 REVIVE method=revive raise_revive=false ... lines_in_window=0
t=5 s=6 EV_DETAIL script_raised_built case=build:A ent=entity-ghost/iron-chest#25 tags_at_raise={design_tag = "kept"}
final EVENT_COUNTS: script_raised_built=261 = 127 entity ghosts + 134 tile ghosts stamped, none from robots or revives
```

## Q2 Unit numbers: does a robot-built or revived entity keep the ghost's unit_number? ghost_unit_number for build_blueprint ghosts?

**Answer** (high confidence). No. Robot-built and revived entities get a new unit_number (ghost #24 became entity #532; revived ghost #27 became #32). ghost.ghost_unit_number is nil for every build_blueprint ghost (0 of 100 in C, and none in the verbose cases). Extra probe E1: when a built instance entity dies, its death ghost has ghost_unit_number equal to the dead entity's number, and the robot rebuild gets that same unit_number back (#552 became #552). Neither the death ghost nor the rebuild event carries tags.

```
t=448 BUILT path=robot case=A ent=wooden-chest#532 ghost_unit_at_pos=24 same_unit_as_ghost=false
t=5 REVIVE ghost=entity-ghost/wooden-chest#27 entity=wooden-chest#32 entity_keeps_ghost_unit=false
t=491 ANSWER Q2 robot_built_entity_keeps_ghost_unit_number=false same=0 of 3 ghost_unit_number_nonnil=0
C_STATS same_unit=0 ghost_unit_number_nonnil=0 (100 ghosts)
t=551 E1 died unit=552 death_ghost=entity-ghost/wooden-chest#582 ghost_unit_number=552 tags=nil
t=1056 BUILT_UNTAGGED path=robot case=A ent=wooden-chest#552 tags=nil
```

## Q3 on_object_destroyed: order relative to on_robot_built_entity, same tick or end of tick, useful_id, built-entity registration

**Answer** (high confidence). on_robot_built_entity comes first, and the ghost is already invalid inside that handler (0 of 100 valid). The ghost's on_object_destroyed fires at the end of the same tick, after all built events of that tick: 100/100 at delta 0, never before the built event. useful_id equals the ghost's unit_number (100/100). A registered built entity fires as expected, with useful_id equal to its unit_number, at the end of the tick it was destroyed. That was seen for destroy(), die() and robot deconstruction (100/100 in C). Script revives and scripted ghost removals also report at the end of the same tick. The 'end of next tick' case was never observed.

```
t=488 s=289 BUILT path=robot case=A ent=small-lamp#555 ghost_valid_in_handler=false
t=488 s=291 BUILT path=robot case=W ent=constant-combinator#556
t=488 s=292 DESTROYED kind=ghost case=A reg=3 useful_id=26 ghost_unit=26 useful_is_ghost_unit=true matched_built=true ticks_after_built=0
t=488 s=293 DESTROYED kind=ghost case=W reg=37 useful_id=63
t=796 C_STATS ghost_delta_hist={[0] = 100} order_bad=0 useful_eq_ghost_unit=100
t=521 VERDICT Q3 built_entity_registration_fires_on_destroy PASS unit=555 useful_id=555 ticks_after_destroy_call=0
t=796 VERDICT Q3 C_ghost_destroyed_after_built PASS delta_hist={[0] = 100} order_bad=0 vanished=0
```

## Q4 Tile ghosts: returned by build_blueprint? unit_number? tags? register_on_object_destroyed? on_robot_built_tile positions?

**Answer** (high confidence). Yes, build_blueprint returns tile ghosts (name 'tile-ghost') together with entity ghosts. Tile ghosts have unit numbers, which the unit_number doc text does not mention. They can be registered: useful_id is the unit number, and on_object_destroyed fires at the end of the tick the tile is built (delta 0: 13/13 verbose, 100/100 in C). They cannot carry tags: writing ghost.tags raises no error but reads back nil. on_robot_built_tile fires with positions and the old tile, one tile per event at vanilla cargo size, with no tags.

```
t=5 STAMP case=T2 returned=5 by_name={["entity-ghost"] = 1, ["tile-ghost"] = 4}
t=5 STAMP_TILE_GHOST case=T1 ghost=tile-ghost/stone-path#38 unit=38 tag_write_ok=true tag_read=nil reg_ok=true useful=38
t=561 TILES_built path=robot case=T1 n=1 positions=19,-14 old="lab-dark-1"
t=561 DESTROYED kind=tile-ghost case=T1 reg=17 useful_id=40 tile=19,-14 tile_built_event_seen=true ticks_after_built=0
t=611 VERDICT Q4 T1_tiles_built_and_events PASS n_tiles=9 placed=9 on_robot_built_tile_positions=9 tile_ghost_destroyed_events=9
C_STATS tile_delta_hist={[0] = 100}
```

## Q5 Item request proxies: insert_plan, proxy after build, creation event, destroyed on delivery, delay

**Answer** (high confidence). BlueprintEntity.items uses BlueprintInsertPlan {id={name='speed-module'}, items={in_inventory={{inventory=defines.inventory.crafter_modules (4), stack=0},{inventory=4, stack=1}}}}. The ghost exposes the same insert_plan, and item_requests={{count=2,name='speed-module',quality='normal'}}. No proxy exists at stamp time. The proxy is created when the entity is built and already exists inside the on_robot_built_entity and script_raised_revive handlers, with entity.item_request_proxy.proxy_target == entity. revive() also returns it as its third value. No event fires when the proxy is created or when the items are delivered. On delivery the proxy is destroyed, which its registration reports through on_object_destroyed (useful_id = proxy unit number), and the modules are in the machine. Build to delivery took 572 ticks (M, busy network), 622 (S, revived) and 544 (M2, idle network). That is one robot round trip from the storage chest about 25-35 tiles away at vanilla robot speed. Building the ghost after stamping took the same 544 ticks.

```
t=5 M item_request_proxies_at_stamp=0
t=5 STAMP_GHOST case=M ... item_requests={{count = 2, name = "speed-module", quality = "normal"}} insert_plan={{id = {name = "speed-module"}, items = {in_inventory = {{inventory = 4, stack = 0}, {inventory = 4, stack = 1}}}}}
t=510 BUILT path=robot case=M ent=assembling-machine-2#560 proxy=item-request-proxy#561 target_is_entity=true requests={{count = 2, name = "speed-module", quality = "normal"}}
t=1082 DESTROYED kind=proxy case=M useful_id=561 target_unit=560 ticks_after_entity_built=572 target_modules={{count = 2, name = "speed-module", quality = "normal"}}
t=5 REVIVE method=revive ... proxy=item-request-proxy#36 proxy_target_is_entity=true lines_in_window=3
t=2551 ANSWER Q5 idle_network_build_to_delivery_ticks=544 stamp_to_complete=1091
```

## Q6 Ghosts that vanish unbuilt: order_deconstruction and destroy

**Answer** (high confidence). ghost.order_deconstruction(force) returns true and destroys the ghost at once. It raises only on_pre_ghost_deconstructed (no on_marked_for_deconstruction). ghost.destroy() raises nothing. ghost.destroy{raise_destroy=true} raises script_raised_destroy. All three report on_object_destroyed at the end of the tick, and no built event ever arrives for them. The fourth (control) ghost was built normally by robots.

```
t=5 EV on_pre_ghost_deconstructed case=V:ghost.order_deconstruction ghost=entity-ghost/wooden-chest#53
t=5 V order_deconstruction returned=true ghost_valid_after=false lines=1
t=5 V destroy returned=true lines=0
t=5 EV script_raised_destroy case=V:ghost.destroy_raise entity=entity-ghost/wooden-chest#55
t=5 DESTROYED kind=ghost case=V reg=30 useful_id=53 matched_built=false
t=623 VERDICT Q6 vanished_ghosts_have_no_built_event PASS ghosts=4 vanished=3 built=1
```

## Q7 Forced mode over trees

**Answer** (high confidence). During the call, build_blueprint raises on_marked_for_deconstruction for each obstructing tree, then script_raised_built for the ghosts. All 3 ghosts were placed. The 3 trees were marked, and a control tree beside them was not. Robots mined the trees (on_robot_pre_mined, on_robot_mined_entity; the wood went to storage), then built the chests with tags (3/3).

```
t=5 s=116 EV on_marked_for_deconstruction case=build:R entity=tree-01@-21.5,15.5 (and two more)
t=5 s=119 EV_DETAIL script_raised_built case=build:R ent=entity-ghost/iron-chest#60 tags_at_raise=nil
t=5 R tree 1 ... to_be_deconstructed=true
t=5 R control_tree tree-01@-14.5,15.5 to_be_deconstructed=false ghosts_returned=3
t=574 VERDICT Q7 forced_over_trees PASS trees_gone=3/3 built_tagged=3/3 control_tree_valid=true
```

## Q8 Recount query and cost for ~100 ghosts

**Answer** (high confidence). The recount was compared with the event-derived expectation every 60 ticks while C (100 entity ghosts on 100 tile ghosts) was building, and matched in 13 of 13 samples. Costs are averages of 100 calls with the full 200-ghost footprint: entity ghosts by find_entities_filtered plus the tags.seb_instance filter, 0.045-0.053 ms; find only 0.012-0.025 ms; count_entities_filtered 0.003 ms. Tile ghosts by find plus a string position-key filter, 0.34 ms (the string building dominates); by find plus a unit-number filter, 0.035-0.044 ms. Proxies by find plus a proxy_target filter, 0.003-0.007 ms. A .valid scan over stored LuaEntity refs, 0.008-0.014 ms per 100. The full recount as first written, with position keys, 0.38-0.43 ms. These timings come from the benchmark run and are indicative.

```
t=796 VERDICT Q8 recount_matches_events_while_building PASS samples=13 mismatches=0
C_RECOUNT ghosts=59 expect=59 tile_ghosts=61 expect=61 proxies=0 match=true
t=5 Q8 cost entity_ghosts find+tag_filter result=100/100 avg_of_100 Duration: 0.049485ms
t=5 Q8 cost tile_ghosts find+key_filter result=100/100 avg_of_100 Duration: 0.343221ms
t=5 Q8 cost tile_ghosts find+unit_filter result=100/100 avg_of_100 Duration: 0.034796ms
t=5 Q8 cost stored_refs_valid_scan result=100/nil avg_of_100 Duration: 0.008390ms
t=5 Q8 cost full_recount result=200/nil avg_of_100 Duration: 0.421331ms
```

## Q9 Wires: red wire between two blueprint entities after robots build

**Answer** (high confidence). Yes. The per-entity BlueprintEntity.wires = {{1, circuit_red, 2, circuit_red}} round-trips through set_blueprint_entities (read back as {{1,1,2,1}}). build_blueprint joins the two ghosts with a ghost wire (connection_count 1, real 0). After robots build both, each has real_connection_count 1, connected to the other.

```
t=5 W blueprint_wires_readback={{1, 1, 2, 1}}
t=5 W ghost entity-ghost/constant-combinator#63 red=1/real=0[entity-ghost/constant-combinator#64:1]
t=491 VERDICT Q9 red_wire_survives_robot_build PASS constant-combinator#554 red=1/real=1[constant-combinator#556:1]
constant-combinator#556 red=1/real=1[constant-combinator#554:1]
```

## Q10 Retirement: entity.order_deconstruction, LuaTile.order_deconstruction, events, exactness

**Answer** (high confidence). Entities: entity.order_deconstruction(force) returns true and raises on_marked_for_deconstruction. Robots then raise on_robot_pre_mined and on_robot_mined_entity, and the entity registration fires with useful_id equal to the unit number. Tiles: LuaTile.order_deconstruction(force) returns a deconstructible-tile-proxy entity, which has no unit number, so registering it gives useful_id 0. The order raises on_marked_for_deconstruction with the proxy as the entity. Robots raise on_robot_pre_mined (entity = proxy) and on_robot_mined_tile (old tile stone-path). The proxy registration fires in the same tick, and the tile reverts to its hidden tile (lab-dark-1). on_robot_mined also fires per item. Removal was exact: two neighbour chests, five neighbour stone-path tiles and the adjacent instance D2 (3 chests, 6 tiles) were untouched. D (3 entities + 6 tiles) retired in 103 ticks; C (100 + 100) in 575 ticks with 100/100 entity destroyed events and 100 tiles mined. Tiles under an entity were mined after the entity above them; that was observed only, not tested as a rule.

```
t=1014 EV on_marked_for_deconstruction case=D entity=deconstructible-tile-proxy@41.5,-6.5
t=1014 RETIRE_ORDERED case=D entities=3 order_ok=3 tiles=6 tile_returned_proxy=6 first_tile_return=deconstructible-tile-proxy@41.5,-6.5
t=1020 DESTROYED kind=entity case=D useful_id=670 unit=670 useful_is_unit=true
t=1049 TILES_mined path=robot case=D n=1 positions=41,-7 old="stone-path"
t=1049 DESTROYED kind=tile-proxy case=D reg=486 useful_id=0 tile=41,-7
t=1117 VERDICT Q10 D_exact_retirement PASS d_entities_gone=3/3 d_tiles_left=0 tile_now=lab-dark-1 neighbours_alive=2/2 neighbour_tiles=5/5 d2_entities=3/3 d2_tiles=6/6 after_ticks=103
t=1401 VERDICT Q10 C_retired_fully PASS entity_destroyed_events=100/100 tiles_still_stone=0 tiles_mined_events=100 after_ticks=575
```

## Q11 Space platforms: does on_space_platform_built_entity carry tags?

**Answer** (low confidence). UNTESTED headless; the entity path is blocked in this harness. The tile path works: build_blueprint places foundation tile ghosts over empty space, the platform builds them, on_space_platform_built_tile fires with positions (old tile empty-space), and the tile ghost registrations fire in the same tick. But on the platform, build_blueprint never created an entity ghost. That held in forced, superforced and normal modes, with skip_fog_of_war=true, on existing foundation, and on P1's foundation after the platform had built it. A ghost made with create_entity and tagged was still unbuilt 2880 ticks later. can_place_entity returns true for script/script_ghost but false for manual, manual_ghost, blueprint_ghost and ghost_revive. That is true for 6 entity types on the platform, and for a fresh create_surface in a Space Age game. In base-only, a fresh surface passes; nauvis passes everywhere except water. None of these lifted it: chart/chart_all, copy_chart from nauvis, clear_chart on nauvis (nauvis still passed), set_surface_hidden(false), associating the probe surface with Vulcanus and unlocking it, unlock_space_platforms, research_all_technologies, creating the platform at runtime (as SRB's tests do) instead of in on_init, or running the save under --start-server instead of --benchmark. Charting never completes headless: is_chunk_charted stays false on every surface, nauvis included. The cause is not identified, and tags on on_space_platform_built_entity need an in-game check with a player client.

```
t=120 STAMP case=P1 pos=6.5,-0.5 returned=9 by_name={["tile-ghost"] = 9}
t=184 TILES_built path=platform case=P1 n=1 positions=5,-2 old="empty-space"
t=184 DESTROYED kind=tile-ghost case=P1 useful_id=555 ticks_after_built=0
t=120 STAMP case=P3 pos=4.5,4.5 returned=0
t=315 STAMP case=P4 pos=6.5,-0.5 returned=0 (on P1's built foundation)
t=7 PDBG can_place check=script real=true ghost=true
t=7 PDBG can_place check=blueprint_ghost real=false ghost=false
t=7 PDBG can_place check=ghost_revive real=false ghost=false
t=7 PDBG platform blueprint_ghost transport-belt=false (also iron-chest, small-lamp, inserter, solar-panel, cargo-bay)
t=7 PDBG new_surface blueprint_ghost iron-chest=false charted=false
base-only: t=3300 BASEONLY new_surface blueprint_ghost=true script_ghost=true
t=3300 CHART after clear_chart(nauvis): nauvis=true
t=3300 RESEARCH after research_all: platform=false platforms_unlocked=true
STATUS t=3000 ... P6=building
```

## Surprises

- Built and revived entities do NOT keep the ghost's unit_number, and ghost_unit_number is nil for build_blueprint ghosts. Death ghosts are the opposite: ghost_unit_number equals the dead entity's number, and the rebuilt entity gets the original unit_number back, but neither carries the seb_instance tag.
- Tile ghosts have unit numbers (the unit_number doc lists only EntityWithOwner, ItemRequestProxy and EntityGhost), can be registered with register_on_object_destroyed (useful_id = unit number), and are included in build_blueprint's return value. Writing tags to them silently does nothing.
- With raise_built=true, script_raised_built fires for tile ghosts as well as entity ghosts, and fires inside build_blueprint before the caller can tag anything. Forced mode also raises on_marked_for_deconstruction for obstructing trees inside the call.
- No event at all fires when an item-request-proxy is created or when its items are delivered. Only a registration on the proxy reveals delivery.
- Under Space Age, the manual, blueprint_ghost and ghost_revive build checks fail on every surface except nauvis in this headless harness (platform and fresh create_surface alike; a fresh surface passes in base-only). build_blueprint then silently keeps only the tile ghosts, and the platform never revives entity ghosts. Charting never completes headless (is_chunk_charted is false everywhere, even on nauvis), yet nauvis is not restricted.
- Vanilla robot travel dominates timing: about 544 ticks to build a ghost about 30 tiles from storage, and the same again to deliver modules, so a primed design needs two robot trips.
- Filtering tile ghosts by string position keys made the recount about 8x slower (0.34 ms vs 0.035-0.044 ms per 100) than filtering by tile-ghost unit number.

## Implications for the mod

- Tag ghosts after build_blueprint returns. The mod's own script_raised_built handler, and any other mod's, never sees seb_instance (DESIGN.md §5, Stamping).
- Key storage.ghost_regs by registration_number, as DESIGN.md already sketches. Unit numbers cannot link a ghost to its built entity; use the tag for the instance and name plus position for the individual ghost.
- Add a global unit_number -> instance index for built entities. An untagged robot build whose unit_number is in that index is a rebuild after the entity died. Without the index the instance silently loses that entity, because rebuilt entities carry no tag.
- Completion tracking: a ghost's on_object_destroyed always arrives after its built event in the same tick. 'Vanished unbuilt' can therefore be decided when the destroy arrives (no built record), or by the recount as n_ghosts - built - remaining. on_object_destroyed is the only signal common to every way a ghost can vanish (order_deconstruction raises on_pre_ghost_deconstructed, destroy() raises nothing).
- Track tile ghosts like entity ghosts, by registration plus a set of unit numbers taken from the build_blueprint result, instead of 'tile ghosts by position'. Keep tile positions anyway for retirement: built tiles have no handle other than position, and on_robot_built_tile carries no tags.
- Register the item-request-proxy inside the built or revive handler, where it already exists. Instance completion then fires on that proxy's on_object_destroyed, with no polling. Stall deadlines must allow two robot trips for primed designs.
- When the mod revives ghosts itself, it should pass raise_revive=true or record the entity directly. A revive without the flag raises no event.
- Recount budget: about 0.05 ms per 100 entity ghosts (find plus tag filter) and about 0.04 ms per 100 tile ghosts (unit filter). A .valid scan over stored LuaEntity refs is about 5x cheaper still and is a true recount, but it cannot see ghosts created later by something else, such as death ghosts. S5 should start from these numbers.
- Retirement works as designed and is exact. LuaTile.order_deconstruction returns a deconstructible-tile-proxy (useful_id 0 when registered); track tile removal via that registration or via on_robot_mined_tile positions.
- Wires and forced mode over trees need no special handling. On nauvis, forced mode also places entity ghosts on top of landfill tile ghosts over water (extra probe E2), so a stamp with landfill allowed can go down in one pass.
- Space platforms, and possibly any second surface under Space Age, must be verified in a real client before the milestone that depends on them. Independently of that, stamping should compare the number of entity ghosts returned against the design and treat a shortfall as a failed all-or-nothing stamp, since build_blueprint drops entities silently.
- DESIGN.md engine facts to amend: tile ghosts have unit numbers and are returned by build_blueprint; built and revived entities get new unit numbers; ghost_unit_number is nil for blueprint ghosts; no event fires on item delivery; 'on_robot_built_tile does not carry tags' is confirmed.

## Not tested here

- Player hand-building (on_built_entity tags), player mining of instance ghosts or entities, the deconstruction planner, undo and redo: all need a LuaPlayer, which cannot exist headless.
- The space platform entity path (on_space_platform_built_entity tags), and entity ghost placement on any non-nauvis surface under Space Age: blocked headless (see Q11), cause unknown. Needs an in-game run with a player client.
- Stamping over existing entities or ghosts (fast-replace, upgrade, a ghost replaced by another ghost) and what that does to tags and registrations.
- Robots with cargo size above 1, where on_robot_built_tile may batch several tiles per event; the handler already loops over event.tiles.
- Non-normal quality items, ghost time-to-live expiry, and the 'end of next tick' timing of on_object_destroyed, which was never observed (every case reported in the same tick).
- FINDINGS.md was not written because the harness blocked it; its content is in this result.

## Follow-up: the Space Age surface restriction is a headless artifact

Checked afterwards in a real client (Factorio 2.1.23 with Space Age, `dev/run-gui.sh space-age`, console probe): on Nauvis, on a Vulcanus surface made with `game.planets.vulcanus.create_surface()` and on a fresh `game.create_surface`, `can_place_entity{name = "iron-chest", build_check_type = blueprint_ghost, forced = true}` returned true and a forced `build_blueprint` created its entity ghost. The restriction seen headless does not exist in a normal game. Space platforms remain unverified.
