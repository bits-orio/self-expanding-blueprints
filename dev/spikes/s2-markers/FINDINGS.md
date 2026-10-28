# S2 Marker settings: findings

Factorio 2.1.23 headless. Re-run with `dev/run-spike.sh s2-markers 1500`.

Written by the orchestrating session from the spike agent's structured report (the harness does not let subagents write report files). Evidence lines are quoted from the spike's final run; long lines are trimmed.

The rig is built in on_init and every case runs at tick 60 of the benchmark, because events raised inside on_init never reach a handler.

Candidates, all with collision_mask={layers={}}, minable with no result, and a hidden only-in-cursor + spawnable item:
- seb-spike-socket: deepcopy of the constant combinator
- seb-spike-socket-nowire: the same with circuit_wire_max_distance=0
- seb-spike-socket-nofrg: the same with fast_replaceable_group=nil
- seb-spike-tagmarker: a simple-entity-with-owner with a Sprite4Way arrow, carrying its settings in tags

VERDICT: use the constant-combinator marker. Its settings are captured from real and ghost markers alike, and they survive create_blueprint, export/import, books, hand-written blueprints and stamping. The tag marker fails the decisive test: a real (non-ghost) entity cannot hold tags. Writing them is a silent no-op, so a blueprint made from a drawn design loses every setting unless the mod arms it in on_player_setup_blueprint.

The combinator marker needs four fixes:
1. Clear fast_replaceable_group. The deepcopy keeps "constant-combinator", so a marker and a real combinator fast-replace each other.
2. Keep signals off wires: circuit_wire_max_distance=0 and/or enabled=false.
3. Ignore sections that belong to a logistic group.
4. Keep descriptions well under 500 bytes.

FINDINGS.md was NOT written: the harness refused report files from subagents. The full findings are in this result.

## Q1 Placement: can the combinator marker be created over entities, another marker, water; as a ghost; what does can_place_entity say?

**Answer** (high confidence). Yes, for both marker types. They can be placed over a chest, a belt, an assembler (centre and corner tiles), a tree, water, a real constant combinator, and a marker of the other type. This holds for create_entity (entity and ghost), for can_place_entity under all six build_check_types (true for entity and ghost alike), and for build_blueprint in normal and forced modes. Nothing gets marked for deconstruction, and 44 of 50 stamps returned the marker ghost.

The other 6 are the exception: a real marker or marker ghost with the same name and direction already on the tile. Then build_blueprint creates no ghost and returns nothing for it, overwrites the existing marker's settings, and raises on_blueprint_settings_pasted (with raise_built=true). A different direction or a different prototype stacks a new ghost. can_place_entity is false only in that same-marker case, and only under manual_ghost and blueprint_ghost for the entity form. Two markers on one tile inside one blueprint both come out, even with the same name and direction.

```
Q1 stamp target=water marker=seb-spike-socket mode=normal ok=true returned=1 ghosts=[ghost/seb-spike-socket@88.5,4.5/d4]
Q1 stamp target=socket_real_E marker=seb-spike-socket mode=normal ok=true returned=0 ghosts=[] at_tile real=1 ghost=0 pre=seb-spike-socket/d4/desc=from-bp events={{dir = 4, ev = "pasted", name = "seb-spike-socket", valid = true}}
Q1 stamp target=socket_ghost_E ... returned=0 ... pre=ghost/seb-spike-socket/d4/desc=from-bp events={{... ev = "pasted", ghost = "seb-spike-socket"...}}
Q1 stamp target=socket_real_N ... returned=1 ... pre=seb-spike-socket/d0/desc=pre-existing
Q1 canplace target=socket_real_E marker=seb-spike-socket as=entity script=true manual=true manual_ghost=false script_ghost=true blueprint_ghost=false ghost_revive=true
Q1 stack_bp same_name_same_dir PASS want 2 marker ghosts on the tile
```

## Q2 Capture of settings: does create_blueprint capture direction, player_description and control_behavior.sections, for a real marker and for a ghost? Can a ghost's settings be written?

**Answer** (high confidence). Yes on every count.

Real marker: combinator_description, get_or_create_control_behavior().get_section(1).set_slot(i, {value={type,name,quality='normal',comparator='='}, min=n}) and section.filters={...} all work, and a fresh marker already has 1 section. create_blueprint captures direction=4, player_description and control_behavior.sections.

Ghost marker: get_control_behavior() returns a LuaConstantCombinatorControlBehavior even before anything is set, and the description and slots are writable. create_blueprint captures ghosts with their settings.

create_entity also accepts player_description and control_behavior (the BlueprintEntity shape) directly, for real entities and for entity-ghost.

```
Q2 capture_real entity={control_behavior = {sections = {sections = {{filters = {{comparator = "=", count = 42, index = 1, name = "seb-spike-target", quality = "normal", type = "virtual"}}, index = 1}}}}, direction = 4, ..., player_description = "Solar block"}
Q2 capture_real PASS
Q2 ghost_write PASS combinator_description and section slots writable on a ghost
Q2 capture_ghost PASS direction=4 player_description=Ghost block filter=seb-spike-target/43
Q2 ghost_params PASS create_entity{entity-ghost, player_description, control_behavior}
Q2 filters_write PASS
```

## Q3 Reading back after a stamp: does the created marker ghost expose its settings; which API calls work on a ghost?

**Answer** (high confidence). Yes. Every call tested works on a stamped ghost:
- combinator_description (read and write)
- get_control_behavior() and get_or_create_control_behavior()
- cb.enabled (read and write)
- cb.sections_count and #cb.sections
- cb.get_section(1).filters, get_slot(1), is_manual, active, multiplier and group
- set_slot, cb.add_section() and cb.remove_section(2)
- ghost_prototype.items_to_place_this, supports_direction and mirroring

ghost.tags is nil unless the blueprint set tags. The ghost read back desc 'Solar block', filter seb-spike-target=42 and direction 4.

```
Q3 probe api=combinator_description ok=true value="Solar block"
Q3 probe api=cb.get_section(1).get_slot(1) ok=true value={min = 42, value = {comparator = "=", name = "seb-spike-target", quality = "normal", type = "virtual"}}
Q3 readback PASS desc=Solar block filter=seb-spike-target/42 dir=4
Q3 rewrite_ghost PASS
Q3 ghost_sections add ok=true got=LuaLogisticSection count_after_add=2 remove ok=true result=true count_after_remove=1 set_enabled ok=true enabled_now=false
```

## Q4 Round trips: export/import, blueprint book, and set_blueprint_entities with player_description and control_behavior

**Answer** (high confidence). All of these preserve direction, player_description and control_behavior exactly:
- export_stack then import_stack (code 0)
- a blueprint inside a blueprint book, exported and imported (code 0); stamping from the book's inner blueprint gives a readable ghost
- a hand-written set_blueprint_entities table with player_description and control_behavior (two filters, one of them negative), which reads back and stamps a ghost with the right settings and direction

```
Q4 export len=381 import_code=0
Q4 export_import PASS identical direction, player_description, control_behavior
Q4 book inserted=1 export len=417 import_code=0 inner_is_blueprint=true
Q4 book PASS
Q4 book_stamp PASS ghost from book blueprint ... desc = "Solar block"
Q4 hand_stored PASS
Q4 hand_stamp PASS ghost stamped from a hand-written blueprint
```

## Q5 Tags baseline: does a tag-marker ghost carry tags after build_blueprint, and do tags survive export/import?

**Answer** (high confidence). Yes, once the tags are in the blueprint:
- set_blueprint_entity_tags then build_blueprint gives ghost.tags, nested tables included
- export/import and a book keep them
- tags passed in the set_blueprint_entities table work
- pasting over a real same-direction tag marker delivers them in on_blueprint_settings_pasted.tags
- pasting over a tag-marker ghost replaces that ghost's tags

Decisive negative: a real (non-ghost) entity cannot hold tags. Writing raises no error and reading back returns nil, so create_blueprint over a real tag marker captures no tags (over a ghost it does).

Tags also work on the combinator marker, so a hybrid is possible.

```
Q5 stamp_tags PASS ghost.tags={nested = {a = 1, list = {1, 2}}, seb_design = 42, seb_target = "Solar block"}
Q5 export_import_tags PASS import_code=0
Q5 book_tags PASS
Q5 real_tag_marker read_tags ok=true value=nil write_tags ok=true read_after_write=nil
Q5 real_entity_holds_tags FAIL
Q5 captured i=1 name=seb-spike-tagmarker x=16.5 tags=nil (real) / i=2 x=18.5 tags={...} (ghost)
Q5 paste_over_real_tags PASS
Q5 paste_over_ghost_tags PASS
Q5 hybrid_socket_tags PASS
```

## Q6 Direction: 4 directions in create_entity and blueprints; does a stamp with direction d give (D+d)%16?

**Answer** (high confidence). Yes for both markers. create_entity keeps 0, 4, 8 and 12; direction 2 (north-east) snaps to 0. The blueprint stores north as nil and 4, 8, 12 as written. All 20 stamps per marker type (D in omitted, 0, 4, 8, 12 times d in 0, 4, 8, 12) give exactly (D+d)%16.

Neither marker records mirroring: mirror=true is dropped from the blueprint and ghost.mirroring is false.

```
Q6 create_entity marker=seb-spike-socket d0->real:0,ghost:0 d2->real:0,ghost:0 d4->real:4,ghost:4 d8->real:8,ghost:8 d12->real:12,ghost:12
Q6 matrix marker=seb-spike-socket D=12 stored_direction=12 d0:got=12,want=12 d4:got=0,want=0 d8:got=4,want=4 d12:got=8,want=8
Q6 matrix seb-spike-socket PASS 20/20 stamps rotate to (D + d) % 16
Q6 matrix seb-spike-tagmarker PASS 20/20
Q6 mirror marker=seb-spike-socket stored_mirror=nil ghost_mirroring=false
```

## Q7 Events and destruction: script_raised_built for marker ghosts with raise_built and no by_player; destroy inside the handler; destroy after return

**Answer** (high confidence). script_raised_built fires once per ghost, marker ghosts included, in blueprint entity order. This holds in normal and forced modes; with raise_built=false no events fire.

Destroying marker ghosts inside the handler is safe for the stamp: the other 4 ghosts survive and nothing is left behind. But the array build_blueprint returns then has nil holes where the destroyed ghosts were. ipairs stops at the first hole, and # can under-report: with the markers last it returned 2 while 4 valid ghosts remained.

Destroying marker ghosts after build_blueprint returns leaves a full array (7 valid) and an area holding only the real design's ghosts (no proxies or other leftovers).

```
Q7 A_normal_destroy_in_handler events=7:[ghost/wooden-chest,ghost/seb-spike-socket(destroyed),ghost/seb-spike-tagmarker(destroyed),...] returned_len=7 valid=4 invalid=0 nil_holes=3 ipairs_sees=1 pairs_sees=4 [1:wooden-chest,2:NIL,3:NIL,4:wooden-chest,5:transport-belt,6:NIL,7:wooden-chest]
Q7 E_markers_last_destroy_in_handler ... returned_len=2 valid=2 nil_holes=0 ipairs_sees=2 pairs_sees=4
Q7 B_normal_destroy_after_return ... valid=7 nil_holes=0 ipairs_sees=7
Q7 B ... destroyed_after=3 left_in_area=ghost/transport-belt,ghost/wooden-chest,ghost/wooden-chest,ghost/wooden-chest
Q7 D_no_raise_destroy_after_return events=0:[]
```

## Q8 Robots and markers: do robots or the network try to fetch the only-in-cursor marker item for marker ghosts in a roboport area? Errors?

**Answer** (medium confidence). Phase 1: marker ghosts of all three types sat in a powered network with 20 robots for 600 ticks with no marker item anywhere. No robot ever queued a marker job: robot_order_queue showed only the control chest's pickup and construct. There were no errors, and the marker ghosts stayed.

Phase 2: a script inserted the marker items into the storage chest at tick 660. only-in-cursor did not prevent that, and the network counted them. Robots then picked them up and built all three markers as real entities by tick 1200.

Alerts could not be checked (per-player only, and there is no player headless).

```
Q8 robots tick=120 r1@201,200 cargo=empty orders=[pickup:storage-chest:wooden-chest;construct:ghost/wooden-chest:wooden-chest]
Q8 status tick=600 phase=1 ... seb-spike-socket:ghost=true,real=0 seb-spike-tagmarker:ghost=true,real=0 seb-spike-socket-nowire:ghost=true,real=0 wooden-chest:ghost=false,real=1
Q8 phase2 chest.insert seb-spike-socket=5 seb-spike-tagmarker=5 seb-spike-socket-nowire=5 network_count seb-spike-socket=5 ...
Q8 robots tick=720 ... orders=[pickup:storage-chest:seb-spike-socket;construct:ghost/seb-spike-socket:seb-spike-socket]
Q8 status tick=1200 phase=2 seb-spike-socket:ghost=false,real=1 seb-spike-tagmarker:ghost=false,real=1 seb-spike-socket-nowire:ghost=false,real=1
```

## Q9 Signals as data: can the socket target be a virtual signal value; does it round-trip through create_blueprint and stamped ghosts? Description length limit?

**Answer** (high confidence). Yes. Signal values round-trip exactly through create_blueprint, export/import and the stamped ghost. Tested: the design number 42, -7, 2147483647 (int32 max), an item signal, and a second section.

combinator_description is silently cut to 500 bytes on every write path: the live setter, set_blueprint_entities and create_entity{player_description}. The cut counts bytes, so it can split a multi-byte UTF-8 character: 200 three-byte characters ended as 168 characters of invalid UTF-8. Text up to 500 bytes, including newlines, non-ASCII and rich-text tags, is preserved exactly.

```
Q9 values_captured PASS / values_imported PASS / values_ghost PASS 1:seb-spike-target=42,1:signal-A=-7,1:signal-B=2147483647,1:iron-plate=5,2:seb-spike-target=7
Q9 desc len500 PASS
Q9 desc len501 set_bytes=501 live_bytes=500 captured=500 imported=500 ghost=500
Q9 desc utf8_3byte_x200 set_bytes=600 live_bytes=500 live_chars=168 live_valid_utf8=false
Q9 long_paths set=2000 set_blueprint_entities_stored=500 export_import=500 stamped_ghost=500 create_entity_param=500
Q9 desc unicode PASS
```

## Extra: wires and circuit behaviour of the combinator marker

**Answer** (high confidence). The deepcopy marker accepts circuit wires (max_circuit_wire_distance=9), and its signals appear in the connected network. Setting enabled=false empties the network within a tick. is_on=false is captured in the blueprint and stamped onto the ghost, and the signals stay readable while it is off.

The nowire variant reports max_circuit_wire_distance=0 and can_wire_reach=false, and connect_to with reach_check=true fails. connect_to without a reach check still connects it and leaks its signal. Whether connectors are drawn on screen could not be checked headless.

```
QX signals tick=120 marker=seb-spike-socket ... network={{count = 42, signal = {name = "seb-spike-target", type = "virtual"}}}
QX signals tick=240 marker=seb-spike-socket ... enabled=false network={}
QX wire marker=seb-spike-socket-nowire reach_check=true connect ok=true result=false can_wire_reach=false connections=0
QX wire marker=seb-spike-socket-nowire reach_check=false ... result=true connections=1
QX disabled_roundtrip PASS
```

## Extra: fast replace, copy_settings and logistic groups

**Answer** (high confidence). Fast replace: the deepcopy inherits fast_replaceable_group 'constant-combinator', so a real constant combinator and a marker fast-replace each other in both directions, destroying the one replaced. With the group cleared they just stack.

copy_settings (what shift-click copy and paste does) copies description and signals between markers and real constant combinators, both ways.

Logistic groups: a section with a group shares its content across the force. The blueprint stores the group name plus the values at capture time (42), but a ghost stamped after the group changed reads the group's current values (99).

```
QX fast_replace cc_over_socket can_fast_replace=true ... base_still_valid=false on_tile=constant-combinator
QX fast_replace socket_over_cc can_fast_replace=true ... base_still_valid=false on_tile=seb-spike-socket
QX fast_replace cc_over_nofrg can_fast_replace=false ... base_still_valid=true on_tile=constant-combinator,seb-spike-socket-nofrg
QX copy_settings cc<-socket ok=true ... desc = "source"
QX group blueprint_section={... count = 42 ..., group = "seb-spike-group"}
QX group ghost_group=seb-spike-group ghost_sees={{min = 99, ...}}
```

## Extra: are events raised during on_init delivered?

**Answer** (high confidence). No. create_entity{raise_built=true} and build_blueprint{raise_built=true} inside on_init (during --create) reached no handler. The same build_blueprint at tick 60 called the handler synchronously, before build_blueprint returned. This was tested once with a temporary probe control.lua; the spike now stamps at tick 60 for that reason.

```
SEB_SPIKE PROBE on_init after create_entity raise_built events=0
SEB_SPIKE PROBE on_init after build_blueprint raise_built events=0
SEB_SPIKE PROBE handler tick=60 name=entity-ghost
SEB_SPIKE PROBE tick60 after build_blueprint raise_built events=1
```

## Surprises

- A real or ghost marker with the same name and direction on the stamp tile suppresses ghost creation. build_blueprint returns nothing for that marker and overwrites the existing marker's settings (on_blueprint_settings_pasted fires). Applies to both marker types.
- Destroying ghosts inside script_raised_built leaves nil holes in build_blueprint's returned array. ipairs stops at the first hole, and # under-reported (2 while 4 valid ghosts remained).
- The deepcopied constant combinator keeps fast_replaceable_group 'constant-combinator'. A real combinator and a marker fast-replace (destroy) each other.
- combinator_description is silently cut to 500 bytes on every write path. The cut counts bytes and can leave invalid UTF-8.
- only-in-cursor items can be put into a storage chest by script. Robots then build real markers from marker ghosts.
- Logistic groups override blueprint values: a stamped marker ghost in a grouped section reads the force's current group content (99), not the value stored in the blueprint (42).
- Real (non-ghost) entities silently ignore writes to LuaEntity.tags (no error, reads back nil).
- circuit_wire_max_distance=0 blocks reach-checked wiring, but connect_to without a reach check still wires the marker and leaks its signals.
- script_raised_built raised inside on_init is not delivered to any handler.
- Neither a constant combinator nor a simple-entity-with-owner records mirroring: a blueprint mirror=true is dropped and ghost.mirroring is false.

## Implications for the mod

- Use the constant-combinator-derived marker. Its settings live in the entity and are captured from real and ghost markers with no arming. The tag marker would need on_player_setup_blueprint arming plus per-marker storage, because real entities cannot hold tags.
- Marker prototype: base it on constant-combinator with collision_mask={layers={}}, fast_replaceable_group=nil or unique, circuit_wire_max_distance=0, and an only-in-cursor + spawnable hidden item. Optionally set enabled=false when a marker is built (is_on survives capture and stamping).
- Carry the socket target as a virtual-signal value in section 1 (design number, exact int32). The description holds only a short display name, kept well under 500 bytes and never used as the key.
- Reject or warn at registration on any marker section with group ~= ''. Grouped content is force-wide and wins over the blueprint's stored values at stamp time.
- Read marker ghosts (position, direction, settings) and destroy them after build_blueprint returns, not inside script_raised_built. If any handler can invalidate ghosts during a stamp, walk the result with pairs and nil-check each entry; never use ipairs or #.
- Clear same-name markers from a stamp footprint first, or treat on_blueprint_settings_pasted for a marker (raise_built=true) as 'marker present'. Otherwise a stamp over the player's drawn seed design or a leftover marker ghost loses that socket.
- Markers never block a normal-mode (all-or-nothing) stamp, whatever they sit on: entities, trees or water.
- Marker ghosts left in the world (for example after a hand paste) are inert to robots while no marker item exists. Still destroy marker ghosts on on_built_entity, and never insert marker items into any inventory.
- Parent socket directions come out of the stamp already rotated ((D+d)%16 holds). Flips need the blueprint rewrite, and a marker cannot report a flip.
- Do all stamping, and all headless tests, during ticks: events raised in on_init are not delivered.
- Blueprint entity tags also work on the combinator marker, so the mod can add internal bookkeeping tags without giving up native settings.

## Not tested here

- Player-driven paths: copy-paste (Ctrl+C/V), select-new-contents, editing a blueprint in the library, on_player_setup_blueprint arming, hand-pasting a blueprint with markers (on_built_entity and by_player), and flips (on_pre_build).
- 'Missing construction material' alerts for marker ghosts: alerts are per player, and there is no player headless.
- Visuals: whether circuit connectors are drawn on the marker or nowire variant, how the constant-combinator GUI presents the description and signals, and the arrow graphics.
- Whether a player can move an only-in-cursor marker item into a chest by hand (script insert works).
- Whether a player can stack two markers on one tile with the cursor (can_place_entity says manual=true except for the same marker in the same direction).
- Blueprint parametrisation of the marker's signal: there is no runtime API for it.
- Loading a blueprint with markers in a game without the mod.
- LuaRecord (game blueprint library) round trips, space platforms, other surfaces, and Space Age quality variants.
- Whether build_blueprint's returned index always matches blueprint entity order (seen in one case only).
