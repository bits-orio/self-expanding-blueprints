# Self-Expanding Blueprints: design

**Mod:** Self-Expanding Blueprints (`self-expanding-blueprints`) · **Target:** Factorio 2.1, Space Age optional · **Status:** v0.1 slice implemented and playtested. v0.2 implements most of this document: the playtest fixes (plug naming, design pictures, project status and history), ore sensors and retirement on depletion, probes and pools, dry runs, update in place and research upgrades, the circuit builder with ten verbs, project order and rules, admin map settings, space platforms, the Land Title Registry and AI Agent Bridge integrations, Tips and Tricks with simulations that run the mod, and a seed-only scenario. Section 8 lists what is still open. Spikes S1 to S3, S5, S6 and S8 run (`dev/spikes/`); S4 answered by update in place (shared parts are never rebuilt) · **Last updated:** 2026-10-26

This is the handoff document for Self-Expanding Blueprints. It is written so an implementer can build v1 without the conversations behind it. Decisions are stated in spec voice. Anything genuinely unresolved is marked **Open:** and collected in the last section. As the vocabulary and the decisions settle, they move into `CONTEXT.md` and `docs/adr/`, as in the other bits-orio repos.

## Contents

1. Overview and identity
2. Core model
3. Player experience
4. The circuit layer
5. Technical architecture
6. Interfaces and integration
7. Competitive landscape
8. Scope, roadmap and decision log

---

## 1. Overview and identity

### What it is

Self-Expanding Blueprints grows a factory from the player's own blueprints. A player names a blueprint, draws arrows into it where the next piece attaches and dots where something must be true underneath, and the mod runs the growth loop: pick the next spot, check it, clear it, stamp it, wait for the robots, pick the next spots.

Every stamp is remembered. It reports when its robots have finished, can be removed exactly, retires itself when its ore runs out, and follows changes to its design. Circuit players drive the same engine with readable signals and get answers back. Other mods drive it through a remote interface.

### The two design tests

1. The floor: a player on a multiplayer server gets a solar field growing within five minutes, without opening Tips and Tricks and without placing a combinator.
2. The ceiling: anything Recursive Blueprints+ can do, this mod can do. The capability checklist in §4 is binding. Simplicity comes from layering, never from removing a capability.

### Problems this design answers

Recursive Blueprints+ (`rec-blue-plus`, FoxLBA, 39,815 downloads) is the incumbent. Reading its source (v1.5.2) and 31 of its portal discussion threads on 2026-10-25 showed the same problems again and again:

- Commands are numbers on one signal: 16 opcodes, 28 custom virtual signals, a 19-bit scanner mask and 7 settings. One signal, `rbp-enviroment`, means three different things depending on the command.
- The most common question is "I sent the signal and nothing happens" ([thread](https://mods.factorio.com/mod/rec-blue-plus/discussion/693e6647cc8ab5b4612f5029)). Two chests look identical and take different signals, and a map setting changes which signal the old one reads.
- Blueprints anchor on their center, and areas on a corner or the center depending on a map setting ([thread](https://mods.factorio.com/mod/rec-blue-plus/discussion/6887d2064558a85fd2625513)). Planet Linox's author showed players a warning to change that setting at game start ([thread](https://mods.factorio.com/mod/rec-blue-plus/discussion/69204de22fdd9e319899a341)).
- Nothing remembers what a stamp placed. Asked to "remove exactly what that blueprint placed", the author suggested stamping wooden chests superforced and filter-deconstructing them ([thread](https://mods.factorio.com/mod/rec-blue-plus/discussion/6a822b6d1244d2c2f3e3fa29)).
- Knowing that a stamp has finished takes a scanner counting ghosts, and its building count includes logistic robots.
- A blueprint cannot carry itself, so copy commands move blueprints between chests. That also breaks remote-view play: a Brave New World player could not put a blueprint into the chest at all ([thread](https://mods.factorio.com/mod/rec-blue-plus/discussion/6a5cd168b35ed72865090dc6)).
- Every chest and scanner is read every tick. The author declined configurable signals partly for that cost ([thread](https://mods.factorio.com/mod/rec-blue-plus/discussion/672bf45f4d256d47bb5a0a35)) and added a wait signal after a performance report ([thread](https://mods.factorio.com/mod/rec-blue-plus/discussion/693d9d7921111dd21a781be3)).
- Signals cannot name another planet or a space platform ([thread](https://mods.factorio.com/mod/rec-blue-plus/discussion/6ab5861034f883b241163a40), [thread](https://mods.factorio.com/mod/rec-blue-plus/discussion/69f0e04a21301e10323f5509)).
- Placing many copies means "looping for minutes with a circuit contraption" ([thread](https://mods.factorio.com/mod/rec-blue-plus/discussion/67334a72f85949ae38c0a23a)).

### What it is not

- It is not a fork. It is written from scratch, and no code is reused from Recursive Blueprints, Recursive Blueprints+ or Simple Recursive Blueprints. If code is borrowed later (all three are MIT), its copyright notice and licence text ship with it.
- It is not a layout calculator. Designs come from the player or from another mod. Working out an optimal drill layout for a patch is Mining Patch Planner's job.
- It is not a numbered-command machine. Circuit control uses named signals (§4).
- It is not tied to one force. Everything is keyed by force and surface, so it serves every Multi-Team Support team.

### Credit and prior art

Recursive Blueprints (Doc, justarandomgeek, DaveMcW) created the genre: a chest that stamps blueprints on circuit command, so a factory can build itself. Recursive Blueprints+ (FoxLBA) carried it to Factorio 2.1 and grew it into a full command set. This mod reimagines that idea; it continues neither codebase.

Ideas that came from other mods, with thanks:

- Simple Recursive Blueprints (Qweasd123tg): a direction-marker arrow inside a blueprint that continues it. Its headless rotation tests are the reference for S1.
- PersistantBlueprints (mrvn): copies linked to a master, with edits propagated as diffs.
- blueprint-deconstruction-markers (Elwin) and Negative Space (Rycieos): marker entities whose ghosts are removed the moment they appear.
- Construction Probe (Eketek): construction costs as circuit pulses.
- AutoDeconstruct (mindmix): retiring drills whose ore has run out.

**Decided 2026-10-27:** the owner has no way to reach these authors, so nothing was asked and no NOTICE records an answer. The README and the portal page credit each of them by name, and say that this mod is a full rewrite that borrows ideas and reuses no code.

### Name rationale

Measured on the live portal on 2026-10-25 and 2026-10-26:

- "Self-expanding" is Recursive Blueprints' own tagline ("build a self-expanding factory"). No portal title or internal name contained it, and Recursive Blueprints+ ranked first for "self expanding" only through its summary, so a title that leads with it should rank first.
- Plural "Blueprints" is a strong query of its own: Simple Recursive Blueprints ranks fourth for "blueprints" with 13 downloads, from its name alone.
- Three hyphenated words match the family: `multi-team-support`, `land-title-registry`, `research-cost-shaper`.
- "Recursive Blueprints" stays out of the title, where four existing titles already use it, and goes in the summary for family searches.
- Search matching: "recursion" finds "recursive" titles and "expand" finds "expanding"; "expansion" does not.
- Rejected: "Self-Building" (in the community it means a factory that crafts its own construction materials, as in Brian's Self-building factory modpack), "Replicator" (Fulgora Replicators, Dark Matter Replicators), "Jigsaw" (a known community member), seed, sprout or growth (Gleba farming), and planner, foreman or masterplan (they read as calculators).

### Design pillars

| Pillar | Commitment |
|---|---|
| Recursion lives in designs | Sockets are drawn into blueprints. A socket can point at a book, and the first design that fits wins |
| Stamps are instances | Every stamp is recorded with its entities. Completion, exact removal, retirement and updates follow from that |
| Full power, readable | Every Recursive Blueprints+ capability, through named signals and a request, ACK, DONE handshake |
| One rule per coordinate | A stamp lands by its entry arrow. An area is a top-left corner plus a size. No setting changes either |
| All-or-nothing stamps | The footprint is checked first. A stamp goes down whole or reports why not |
| Event-driven | No unconditional `on_tick`. Work runs from events and one self-registering due-tick queue |
| Any force, any surface | Keyed by force and surface: every MTS team, every planet, space platforms |
| Built to be built on | A stable remote interface and custom events from v1 |

---

## 2. Core model

### Vocabulary

| Term | Meaning |
|---|---|
| Design | A blueprint registered under a name and a stable number, with a version |
| Library | A force's designs. Entries can also reference records in the map's game-blueprints library |
| Socket | An arrow marker inside a design: another design attaches here, facing this way |
| Entry | The arrow marker that says where a design attaches. It is the design's anchor. Players see it as the Plug: it goes into a socket (D24) |
| Ore sensor | A marker whose watched area must run out of ore before the copy's sockets open (D28) |
| Pool | A blueprint book a socket points at. The first design in it that fits is stamped |
| Probe | A tile marker inside a design, stating a fact that must hold on that tile |
| Instance | One stamp of one design version, with its transform, footprint and entities |
| Project | One growth run: a seed design, a surface and place, rules and gates |
| Port | A combinator in a design, marked as the instance's circuit mailbox |
| Parameter | A per-instance value (a signal, a number or a name) filled in at stamp time |

### Designs and the library

- A design is registered from a blueprint in hand, from every entry of a book, from a blueprint string through the remote interface, or by referencing a record in `game.blueprints`. v0.2: `register_design` takes the record (or an item stack) itself as well as a string; it registers the record as it is then, and editing the record later makes a new version only when it is registered again.
- Each design has a stable number (what circuits use), a name, an icon and a version. Registering an edit creates a new version, and instances keep the version they were stamped from.
- Per version, the mod prepares and caches the socket, entry and probe markers, the footprint for each direction, the entry offset for each direction (§5), and `cost_to_build`.
- Libraries are per force, so each MTS team's designs are its own.
- Exporting and importing a library: the window's book button (and `export_library`) gives every design as one blueprint book; adding that book in another save registers each blueprint again (v0.2).
- v0.2 (D45): a force holds at most `seb-max-designs-per-force` designs (a new version is always allowed), and never more than 30,000 whatever the setting says (0 means that much); a design wider or taller than 512 tiles, markers included, with more parts than `seb-max-design-parts` (every entity, markers included, and every tile) or with more than 64 drawn sockets or 1,000 electric poles is refused before any lab work. The size limits apply when a design or a new version is registered: one prepared again after a mod change keeps working under a lowered cap. Registering is charged to the force's share of server time (D44), by its parts, by the lab chunks its calibration and picture need made (a few parts far apart can span hundreds) and by the length of its blueprint string, refused or not (exporting a big blueprint takes about a second per 100,000 parts); the window and a book added from it never export a blueprint with more parts than a design may have, told from its entity count and the tiles of its bill of materials. Each registration also pays a fixed part for its calibration stamps and picture. A book added from the window registers a few designs per run of the due-tick queue while that share lasts; a book whose walk would look at more than 1,000 children (empty blueprints, planners and the books inside with what they hold) is refused before anything is copied, from the window and the remote interface alike. After a mod change designs are prepared again a few per run, and at once when one is used.

### Sockets and alignment

- A child design is placed so that its entry arrow lands on the parent's socket and faces it. A design without an entry arrow attaches by the middle of its back edge, unturned, so its first row sits on the socket's tile (D18).
- A socket targets the same design, a named design, or a pool.
- Parent sockets' world positions and directions follow from the same calibrated transform as everything else (v0.1 computes them; the marker ghosts the engine creates are only checked, the entry against its target, and destroyed). Child placement uses per-direction entry offsets measured on a calibration surface (§5).
- A socket opens when its instance completes, so growth runs exactly as fast as the robots.
- Before stamping, the child's footprint is checked against the index of instance footprints. A socket whose child would overlap another instance closes as joined. One whose child would overlap the instance it grows from closes as overlaps-parent, unless nothing else is in the way and either the project superforces, so the child is built over its parent, the parent's parts in its way replaced like any of the force's own buildings (D54), or the parent is going for depletion: then the socket waits for it to be removed (§2 Depletion, D53).
- An option to open sockets immediately, for fast fills: `open_early` (v0.2, remote interface). A copy's sockets open when it is placed, not when it is built; copies waiting for their ore still wait. Raise `max_building` with it, or the capacity gate still paces the fill.

### Depletion

A mining design can wait for its ore (D28, asked for after the v0.1 playtest: growth should go on when a chosen area is mined out, which is often smaller than a drill's whole area).

- An ore sensor drawn into a design makes its finished copies open their sockets only once no ore is left in the area it watches. On a mining drill it watches that drill's mining area; with its signal R set it watches the square of 2R + 1 tiles around it, smaller or larger than a drill's; anywhere else, its own tile. With several sensors, every watched area must run dry. A copy whose areas hold no ore when it is finished opens at once.
- The project option "Remove copies whose ore runs out" (`retire_depleted`) retires a finished copy once none of its drills has anything left to mine (resources of the drill's categories in its mining area), after a short delay for its output to drain.
- A socket whose child would stand on the copy it grows from waits instead of closing while that copy is going for depletion: it is being removed for it, or its project retires depleted copies and its drills have run dry or its sensors see no ore left. The socket leaves the frontier (`parent-retiring`, drawn on the map, and the row's reason once nothing else is happening) and goes back when the copy is gone, on its retirement rather than a timer. So a design can lay a different piece on the ground its miner stood on: a drill moves on along its ore, and the belt piece its socket names goes down behind it (D53). Anything else in the child's way still closes the socket as joined. A plan mines nothing and opens a copy's sockets at once, so it plans that piece over a copy with drills and sensors.
- Both are event-driven: `on_resource_depleted` looks up the copies watching that chunk in an index of watched areas and checks them again a little later by counting what is left. Nothing polls.
- A copy has at most one look of each kind queued (`ore_check_tick`, `drill_check_tick` on the instance): a run of depleted tiles under it asks for one, made a delay after the first. A look counts what is left with one engine count that stops at the first resource (`scripts/core/resources.lua`) instead of listing a sensor's whole square; a resource bigger than a tile (oil, lithium brine) is judged by its centre as before (D45).

### Probes and rules

- v1 probe predicates: a resource under the tile (any resource, or a named one), a water tile, not a water tile. Implemented in v0.2 (D30): a probe's signals say which. No signal means some resource; an entity signal names a resource, an item or fluid signal the resources that yield it; the fluid signal water asks for water; the signal "deny" negates. A failed probe closes the socket as "probe", or moves a pool on to its next design.
- Rules on a design or a project: charted chunks only; land the team holds (Land Title Registry); a minimum distance from enemy structures; stop after N instances; stay inside a rectangle or radius; landfill allowed or not. v0.2 has them all as project rules (`charted_only`, `enemy_distance`, `max_instances`, `area`, `radius`, `landfill`), set through the remote interface; the window sets the count and the area (a drag).
- Checking a footprint costs one `can_place_entity` per part and one `get_tile` per design tile; area counts (`count_entities_filtered`, `count_tiles_filtered`) run once per stamp, or only to name why a spot was refused. Spike S5 measured 10 to 15 µs per entity for the whole stamp.

### Instances

States: queued → checking → stamping → building → complete. Side states: blocked (with a reason), stalled (deadline passed), incomplete (a ghost vanished unbuilt), retiring → retired, and outdated (a newer design version exists). v0.1 records six of them on each instance (ADR-0010): building, stalled, complete, incomplete, retiring and retired; checking and stamping happen within one tick, and a blocked socket never becomes an instance.

An instance records its id, design id and version, force, surface, position, direction, footprint, parent instance and socket, children, entity unit numbers, tile positions, state, reason, created tick and last progress tick (its stall deadline is STALL_TICKS after that).

### Projects: the growth loop

1. Take the next open socket. Breadth-first by default; depth-first and nearest-first are options (`order`, v0.2).
2. Resolve the target: a design, or each design of a pool in order.
3. Check rules, probes, overlap, gates and caps. The first design that passes is stamped.
4. Stamp it, all or nothing (§5).
5. Track it to completion, then open its sockets.
6. Repeat until no socket is open, a stop rule fires, or the project is paused.

Every socket that closes records why: blocked by water at a map position, outside held land, count reached, joined another instance.

Gates: materials (`cost_to_build` against the logistic network, minus a reserve), the share of idle construction robots, ghosts in flight per project and per force, and an optional circuit condition. v0.2: materials, copies in flight per project (`max_building`), the idle-robot share and copies in flight per force as map settings (D35), and the circuit condition as the builder's Pause signal on a project it grows.

---

## 3. Player experience

### Level 1: Grow

Select a design, press Grow, choose directions or drag a rectangle to fill, and optionally set a count. Level 1 uses implicit sockets on the design's footprint edges, so a plain blueprint with no markers tiles in the chosen directions. No markers, no circuits. The first copy goes down where the player clicks even if no construction robots reach it yet, as a pasted blueprint would; its ghosts wait for robots or the player's hands, and later copies wait for robots to reach their spots (D37).

### Level 2: drawing the growth

Place socket arrows, entry arrows and probe dots while drawing a design. Point a socket at a book to get variants: corner pieces at the edge of a field, a junction every few rail blocks, a different outpost for each ore. v0.2: the window's marker row hands out sockets, plugs, ore sensors, probes, ports and Keep clear markers; a labelled book becomes a pool of its designs under the book's name (D31). Keep clear marks a tile the design needs empty, inside the build or past its edge: it counts in the copy's footprint, so other copies keep off it; trees and rocks on it are cleared when the copy is placed; a building on it refuses the spot, or, superforced, is marked for removal (D41).

### Level 3: circuits and other mods

The circuit layer (§4), ports, parameters and the remote interface (§6).

### Seeing the plan

- The overlay draws open sockets as arrows and the next stamps as outlines, colored by state: queued, building with N ghosts left, waiting for materials, blocked with the reason and a map link. v0.2 draws the next open sockets as arrows (at most 100 per project, and as many of those no robots reach), copies under construction as outlines with "Building: N left", waiting and stalled copies with why, and blocked spots as a red cross with the reason. Instead of a map link, the project row's locate button goes to where it grows now, and its history names each blocked spot's position.
- Dry run grows a plan as outlines only, so a player sees what a recursive design will do before any ghost exists. v0.2 (D33): "Plan only" in the Grow section runs every check, places no ghost, stops at 400 copies without a count, and a finished plan is grown for real from its row. It can also paste its first few copies as look-only ghosts, so the player sees the buildings themselves (D40).
- The project window lists projects and instances with their states and reasons, and offers pause, resume, retire, update to the latest version, and show on map. v0.2 lists projects with a status light (growing, waiting, stalled, paused, finished), what holds them in words, and their history in the tooltip; a copies panel lists the project's copies that need a look (building, stalled, incomplete, waiting for ore, outdated), each with locate, update and remove; a finished copy is removed with the grow tool's right-drag.
- Every design has a picture: hovering a design shows a camera onto its copy on a hidden gallery surface, built there as ghosts of the design's force (D27).
- Growth shows where it goes next: while a copy is built (or waits for its ore), a faint arrow marks each socket it will open and a dashed outline shows the copy that socket would bring, so a field under construction reads as one that will keep expanding (D38). Spots a rule already rules out (count reached, outside the area, a copy already there) show nothing.
- Stopping a project takes every mark it drew off the map; its copies stay, and robots finish the ones under construction (D25).

### Remote view and teaching

- Everything works from map and remote view, and nothing has to be put into a chest. That covers Brave New MTS, where placing blueprints is the only way to build.
- "How growing works" is a window of its own, opened by the question mark in the main window: one tab per marker (sockets and plugs, ore sensors, probes, ports, Keep clear), each a picture and a few lines and a link to its Tips and Tricks entry. It is never the player's opened GUI, so it stays open beside the main window and while the player draws a build on the map; it drags by its title bar and reopens where it was left, on the last tab (D36).
- Tips and Tricks has one entry per use case, each with a short text and a simulation that runs the mod itself (`mods = {"self-expanding-blueprints"}`, chunks declared generated on a checkerboard). Negative Space ships working examples of scripted simulations. v0.2 ships 21 entries in three groups (`prototypes/tips/`): growing (the click, sides and counts, filling an area, obstacles, replacing buildings, waiting for materials, removing copies), markers (sockets and plugs, turning corners, growing another design, pools, probes, Keep clear, ore sensors, removing mined-out copies) and advanced (plans, fast fill, updates and research, the blueprint builder, stamping a grid, ports).
- **Open:** whether player-started stamps join the undo queue. Retiring an instance removes it either way.

---

## 4. The circuit layer

### Principles

- No magic numbers: each verb is a named signal with an icon.
- No packed numbers: each option is its own signal.
- No signal with two meanings.
- No map setting changes what a signal or a design means.

### The builder

A small combinator-style entity with red and green inputs and an output. It runs one request at a time.

Decided in v0.2 (D29): the **blueprint builder**, a decider combinator underneath for its two connectors (players cannot open its decider settings; it shows its own window with every signal it understands). Requests and data arrive on its input, red and green summed; its answers come from a hidden constant combinator the script wires to its output. It runs one request at a time and acknowledges the next only after the current one is done, so the queue depth is one and a program simply holds its next request. There is no engine event for a circuit changing, so a wired builder is read every 12 ticks and one with no wire and no request once a second (Handshake).

### Verbs

| Verb | Inputs | Result | Replaces in Recursive Blueprints+ |
|---|---|---|---|
| Stamp | Design, X, Y, Rotation, options (parameters: open); optional grid count and spacing | The first copy's number and the count built; DONE when built | Commands 1 and 2 |
| Grow | Design, X, Y, Rotation, Count, sides; Pause and Stop while it runs | A project, its status while it runs; DONE when it finishes or is stopped | Deployment loops built from combinators |
| Clear | X, Y, W, H; item signals as a filter; options | DONE when deconstructed | Commands 10 and 11 |
| Upgrade | X, Y, W, H; item signals as a filter; Cancel (v0.2: each entity goes to its default next tier; upgrade planners are not designs) | DONE when upgraded | Command 20; command 1 with a planner |
| Remove | Instance | DONE when removed | The wooden-chest workaround |
| Sense | X, Y, W, H; one category | Counts on the output | The area scanner |
| Find | Design, radius | X and Y of the nearest fit, or an error | Scanner sweeps across many ticks |
| Read | Instance | The port's signals on the output | Commands 30 and 34 |
| Write | Instance; signals on the data input | The port updated | Commands 31, 32 and 33 |
| Capture | X, Y, W, H | A new design number | On FoxLBA's own wishlist |

### Handshake

- A request is a verb signal whose value is a non-zero request number, held on the input together with its parameter signals.
- The builder answers ACK with that number when it accepts the request, then DONE with the same number when the work is complete, or ERR with the number and one named error signal.
- The program drops the request after ACK and may send the next one. The builder shows each DONE or ERR for at least one read before it takes the next request, so a program that sends its next request on ACK still sees the answer. Stop on the input ends whatever runs: Grow stops its project and answers DONE; any other verb answers ERR "stopped" and leaves what it started (ghosts, orders) to the robots.
- Requests are held until acknowledged, so the mod can read wired builders every few ticks without missing any. A builder with no wire on its input and no request running is looked at once a second. A wired one is read every 12 ticks, but a read looks only at the ten verb signals (or at Stop and Pause while a request runs) and copies the whole input once, when it takes a request (charged to its team by the signals it copies, D44), so idle builders cost next to nothing.

### Coordinates

X and Y are relative to the builder unless the Absolute signal is set. A stamp lands by its design's entry arrow, or by the vanilla anchor if the design has none. An area's X and Y are its top-left corner, and W and H its size.

### Errors

Named signals: blocked by water, blocked by cliff, blocked by building, outside held land, uncharted, missing materials, unknown design, out of range, not found. v0.2 adds invalid request, no resource, probe, incomplete and stopped. A Stamp whose copy stalls where no robots reach answers out of range, one that stalls for items the network lacks answers missing materials, and a request that points off the map (past 1,000,000 tiles) is refused as invalid before anything is looked up. Since D45 the error "limit" says a server limit for the team stopped the request: too many projects or designs, a design too big, or a design with too many sockets. A builder past the team's builder limit shows it alone, without taking a request. Running out of the team's share of server time is never an error: the request waits.

### Status outputs

Ghosts left, open sockets, blocked sockets, instances built, and the next stamp's bill of materials as item signals, ready to feed train logistics. v0.2: a running Grow shows all of them (the materials are those of the design its next socket would stamp); a running Stamp shows ghosts left and its copy number. A Grow finds the copies being built by their ids, which only grow, a few hundred per read, and works the materials out once a second, so a project of thousands of copies costs a read next to nothing (D44). Once its request ends the builder goes on showing what it showed then, until the next request.

### Capability checklist

| Recursive Blueprints+ | This mod |
|---|---|
| Deploy at computed X and Y, with rotation and superforce (1) | Stamp with the same inputs; superforce is an option signal |
| Book slots through six layer signals; library index | Design number, or a match by icon |
| Parameter substitution (2) | Per-instance parameters |
| Area deconstruct, filtered deconstruct, upgrade and cancel (10, 11, 20) | Clear and Upgrade with option signals (v0.2: item filters and the Cancel signal) |
| Remote combinator read, write, toggle and clear; remote wire read (30 to 34) | Read and Write addressed to an instance's port |
| Clear output, reset I/O (40, 41) | Outputs belong to a request |
| Copy a blueprint by wire, coordinates or library; delete it (100 to 102, 120) | Designs are referenced, never carried |
| Area scanner (11 counters, item lists) | Sense, one category per request |
| Wait before repeat | Requests are acknowledged |
| Logging to chat on an L signal | Named errors, the overlay and the project history |

v0.2 implements every verb above. Parameters (per-instance values) are not: no runtime API reads or writes blueprint parameters (§5), so that row of the checklist stays open.

**Open:** an optional add-on that speaks Recursive Blueprints+'s exact protocol on top of this engine, kept out of the core.

---

## 5. Technical architecture

### Engine facts this design stands on

Verified in the Factorio 2.1.23 API docs (`runtime-api.json`, `prototype-api.json`) on 2026-10-25:

- `LuaItemCommon.build_blueprint` and `LuaRecord.build_blueprint` return the array of created ghosts. Their parameters are surface, force, position, direction, build_mode, skip_fog_of_war, by_player and raise_built. There is no flip parameter.
- `LuaEntity.tags` is readable and writable on ghosts.
- `on_built_entity`, `on_robot_built_entity`, `script_raised_revive` and `on_space_platform_built_entity` carry tags. `on_robot_built_tile` does not.
- `LuaRecord` has `get_blueprint_entities`, `build_blueprint` and `cost_to_build`. `LuaGameScript.blueprints` lists the game-blueprints library records.
- No runtime API reads or writes blueprint parameters on `LuaItemCommon` or `LuaRecord`.
- `on_player_configured_blueprint` exists and carries no stack or record. `on_pre_build` carries `flip_horizontal`, `flip_vertical` and `mirror`.
- `LuaEntity.mirroring` is readable and writable. `LuaEntity.item_requests` and `item_request_proxy` are readable.
- `on_resource_depleted` and `on_research_finished` exist.
- `TipsAndTricksItem` has `simulation`. `RadarPrototype` has `connects_to_other_radars`.

From other mods' code and docs, not yet reproduced here:

- Negative Space builds its marker on an assembling-machine prototype because its author found it the only kind that mirrors with a blueprint, and gives it an asymmetric collision box so the mirror applies.
- A blueprint that contains a modded entity loads in a game without the mod, with that entity dropped (blueprint-deconstruction-markers README).
- `build_blueprint`'s anchor for rotated, even-sized and odd-sized blueprints follows a transform that Simple Recursive Blueprints derived empirically and covers with a headless rotation matrix. Reflection needs the blueprint rewritten: positions, directions, orientations, inserter vectors, splitter priorities and mirroring.
- Planetary chunks must exist before a stamp. Requesting them and polling avoids synchronous generation (Simple Recursive Blueprints).
- An `on_nth_tick` handler registered at runtime must be registered again in `on_load`, or multiplayer joins fail (AutoDeconstruct 0.3.10 and 0.3.11).
- Stamping new settings over a built machine deleted its contents instead of moving them to the trash slots (Recursive Blueprints+ thread; Wube forum topic 130518).
- Pasting a blueprint over existing entities resets their settings with no event a mod can see (Blueprint Variables README).

From Blueprint Primer's headless spikes, in this family:

- `build_blueprint` honours a blueprint entity's item requests, so primed designs keep them.

Measured in this mod's spikes S1 to S3 on 2.1.23 (`dev/spikes/*/FINDINGS.md`):

- `build_blueprint` places every entity by a rigid transform: the rotated centre of the tile-footprint bounds (tile size, not collision box) lands on the position. It is translation invariant for whole-tile positions; rail-grid designs only for even ones. Relative snapping is ignored; absolute snapping snaps the position.
- The returned array holds tile ghosts first, then entity ghosts. Tile ghosts have unit numbers and can be registered. Built and revived entities get new unit numbers, and `ghost_unit_number` is nil for blueprint ghosts.
- `can_place_entity{name, build_check_type = blueprint_ghost, forced = true}` predicts forced mode exactly. There is no tile placement check.
- No event fires when an item-request-proxy is created or delivered; only its destruction shows delivery.
- Events a mod raises during its own `on_init` never reach its own handlers.
- Headless, chart requests never complete, and under Space Age entity ghosts would not place on surfaces other than Nauvis. A real client places them on Vulcanus and on fresh surfaces, so the latter is a headless artifact; space platforms are still unverified.

### Registry

The registry in `storage` is the single source of truth. The overlay, the circuit outputs and the GUIs are derived from it.

As built in v0.1:

```lua
storage.libraries[force_index] = {inventory, designs = {[design_id] = design}, by_name, next_name}
  -- design = {id, force_index, name, version, icon, slot, stamp_slot, prepared, stale}   -- stale after a mod change (stale.lua)
storage.instances[instance_id] = {
  id, design_id, version, force_index, surface_index, project_id, parent, socket_index, children,
  position, direction, footprint, repeat_size, sockets, sensors, -- recorded at stamp time
  waiting_ore, drill_areas, ore_check_tick, drill_check_tick,     -- depletion (v0.2; one look of each kind queued, D45)
  prepared,                                                       -- its version's prepared data, shared with the design (under.lua)
  entities = {[unit_number] = LuaEntity}, expected, slots = {[position_key] = name},   -- slots while building
  tiles = {[tile_key] = tile_name}, tile_units, tile_count,
  state, reason, ghosts_left, created_tick, last_progress_tick,   -- stalls STALL_TICKS after the last
}
storage.projects[project_id] = {
  id, force_index, surface_index, design_id, directions, rules, gates,
  frontier = {socket...}, parked = {socket...}, blocked, closed = {[reason] = n},   -- frontier in no order (socket.slot)
  frontier_queue = {first, last, [i] = socket}, frontier_seq,   -- the order sockets are tried in (frontier.lua)
  instance_ids, count, building, state, gate, missing_raised, waiting_logged, shown_key,
  stalled = {[instance_id] = reason}, waiting_ore = {[instance_id] = true},
  history = {{tick, kind, count, reason, item, item_count, position, instance_id, player_index, copies}...},
}
storage.meta = {version}                                 -- schema version
storage.next_instance_id, storage.next_project_id, storage.next_design_id
storage.ghost_regs[registration_number] = instance_id   -- ghosts, tile ghosts, proxies
storage.entity_regs[registration_number] = instance_id  -- built entities
storage.footprints[surface_index][chunk_key] = {[instance_id] = true}
storage.queue, storage.queue_armed, storage.queue_min   -- due-tick work items {kind, id}, see ADR-0005
storage.chunk_waits[surface_index] = {[project_id] = true}   -- woken by on_chunk_generated
storage.force_projects[force_index] = {[project_id] = true}   -- each force's projects (registry.lua)
storage.turns[force_index] = {ids, waiting, due, serving}      -- projects waiting their turn for the team's share (pace.lua); made on first use
storage.renders = {instances = {[id] = {objects}}, next = {[id] = {key, objects}},
  projects = {[id] = {sockets, parked, blocked = {[item] = {key, objects, pass}}, planned = {objects}, pass}}}   -- marks.lua
storage.gallery = {next_x, cells = {[design_id] = {left, width, height, footprint, version}}, free}   -- design pictures; free stretches
storage.budgets[force_index] = {level, tick}                  -- each team's share of server time (budget.lua)
storage.server_budget = {level, tick, clock, refused, teams = {[force_index] = {used, refused, served, took, took_tick, piece}}}   -- the whole server's account and its turns (server_budget.lua); made on first use
storage.limit_overrides[force_index] = {[limit] = value}      -- set_limits (limits.lua)
storage.stamps_in_flight[force_index] = n                     -- copies its builders' Stamps have in flight (circuit/flight.lua); made on first use
storage.builders_working[force_index] = n                     -- its builders taking requests (circuit/roster.lua); made on first use
storage.builders_waiting[force_index] = {id, ...}             -- its builders past the limit, oldest first (roster.lua); made on first use
storage.builders_active[id] = true                            -- the builders taking requests: the only ones the timer reads; made on first use
storage.builders_due = tick                                   -- when the builders timer is queued (circuit/builder.lua)
storage.book_jobs[force_index] = {id, player_index, inventory, records, count, next, ids, pool, library, failure, unread}   -- a book added from the window (gui/book_queue.lua); made on first use; storage.next_book_job numbers them
storage.update_lines[force_index] = {ids, first, last, batch_of, batches, next_batch, due}   -- copies waiting to be updated in place (update_queue.lua); made on first use
storage.reprepare_queued                                      -- stale designs are being prepared again (stale.lua); made on first use
storage.watches[kind][surface_index][chunk_key] = {[instance_id] = true}   -- kind "ore" | "drills"; made on first use
storage.players[player_index] = {selected_design, tool_design, grow, window_location}
```

### Completion tracking

- After a stamp, every returned ghost gets the tag `seb_instance = id` and an `on_object_destroyed` registration mapped to the instance.
- A built event carrying the tag adds the new entity's unit number to the instance and registers the entity.
- Any registered ghost disappearing marks the instance dirty. A recount runs once things have been quiet for a short while: tagged ghosts inside the footprint, the instance's tile ghosts by unit number, and item-request-proxies that target its entities.
- Zero left means complete. Counts are always recomputed, never decremented; Constructron's counters drifted at least six times over its history.
- A ghost that vanished without a matching built entity makes the instance incomplete, and the overlay shows where.
- Each instance has a deadline. Passing it with no progress sets stalled, with the best known reason.

### Stamping: all or nothing

- The copy is pre-checked: other instances (the overlap index), charted chunks and enemy structures over its footprint; under its parts only, water without landfill, cliffs (blown up instead when the team has researched cliff explosives), held land, and buildings that are not part of the design.
- Trees and rocks are left to forced build mode, which marks them for deconstruction.
- Then `build_blueprint{build_mode = forced, raise_built = true}` runs. Marker ghosts are read and destroyed in the same tick.
- A stamp that still comes out short, or whose entry lands off its target, is rolled back whole (D15, ADR-0003).

### Placement and calibration

- Parent sockets follow from the calibrated transform, already rotated (v0.1); marker ghosts are checked and destroyed in the stamping tick.
- Placing a child needs the offset from `build_blueprint`'s position to the design's blueprint origin, for each direction; where the entry lands follows from it. It is measured once per design version on a hidden calibration surface: the stamping copy (snapping cleared, one anchor entity added inside its bounds) is stamped at the origin in each direction with `raise_built = false`, the anchor's ghost gives the offset, and everything is destroyed. S1 cross-checks the result against Simple Recursive Blueprints' transform. The copy is built at the lab origin, which build_blueprint centres it on, so the lab work is the design's own size, not its distance from the blueprint origin; only the chunks it covers are asked for.
- Flipped stamps need the blueprint rewritten, and Simple Recursive Blueprints' reflection is the reference. **Open:** flips in v1.

### Markers

- Socket, entry and probe markers (v0.2 also ore sensors, ports and Keep clear) are entities placed while drawing a design. Their ghosts are destroyed the moment a stamp creates them, so they never need items or robots.
- Markers are constant combinators with an empty collision mask and an empty collision box (a point: a marker is a note in a design, not a building, so other mods' ground rules that measure a building's box leave it alone; D42); a socket names its target design in its description, which every blueprint stores natively (D13, ADR-0001). A probe's or sensor's settings are the signals set in its combinator (D28, D30).

### Retirement, depletion and updates

- Retirement: `order_deconstruction` on the instance's entities and tiles. The instance is retired when they are gone, and its footprint leaves the overlap index; sockets waiting for it to go return to the frontier then (§2 Depletion). The record is then forgotten right after `on_instance_retired` (`scripts/core/forgetting.lua`, D45); a copy retired for depletion stays on record while its project grows or is paused, because growth parents from it, and goes when the project ends (stops or finishes) or is forgotten (`instances.forget_retired_of`). Saves from before D45 are swept on a configuration change.
- Depletion: `on_resource_depleted` finds the instances watching the position. After a short delay the drills' mining areas are checked for anything left they can mine, output gets time to drain, and the instance retires. This is AutoDeconstruct's pipeline without its topology guessing, because the instance already knows its entities. Implemented in v0.2 as the `retire_depleted` project option, beside ore sensors (§2 Depletion).
- Update in place: the instance's version is diffed against the new version by relative position and name. Removed entities are deconstructed, added ones stamped, changed ones re-stamped. v0.2 (D32, which answers S4): the new version is laid over the copy where most of its parts coincide with the copy's built entities (blueprint coordinates move when a blueprint is edited; ties go to the copy's own blueprint origin), and built superforced there. A part both versions share is never rebuilt (the paste keeps it and gives it the new settings), so its contents stay; dropped parts are deconstructed; a building or ghost of anyone else's under a part the new version adds, or under its tiles and Keep clear tiles, refuses the update.
- Research-driven upgrades: a design can name a technology that moves its instances to the next version (`on_research_finished`). v0.2: a research chooser on each design row; when the force finishes it, every copy of the design is updated in place to the newest version.
- Updating many copies (a project's update, a research, `update_project`) queues them in the force's line of updates (`scripts/core/update_queue.lua`), served a few per run of the due-tick queue while the team's share of server time lasts; one copy's update (the copies panel, `update_instance`) is made at once. Each update is charged to the team by its parts, its new parts and its footprint's chunks (a copy from an older save that does not record where its parts are, by its footprint's tiles too), and looks only at what changes: a part that already stands is not checked again, and only what stands under a new part, tile or Keep clear tile can refuse it.

### Scheduling and UPS

- No unconditional `on_tick`. Work runs from events and one due-tick queue, whose `on_nth_tick` handler registers itself while the queue holds work and is registered again in `on_load`.
- Stamps and recounts run under per-tick budgets. Find queries are time-sliced; Mining Patch Planner's task runner is the reference. v0.1 budgets each project's advance (a stamp costs four socket checks' worth of work) and leaves recounts unbudgeted, at about 0.05 ms per 100 ghosts (ADR-0004). Spike S5 measured a stamp at 10 to 15 µs per entity; v0.2 charges a stamp by its size (one unit per 32 parts, entities and tiles, at least four) against sixteen units per run of the queue (every six ticks at most), and another stamp goes ahead only while the work left covers the last one's cost, so a design of some hundreds of entities stamps at most one copy per run; the builder's Find tries at most forty spots per read, and only while its team's share of server time allows.
- Builders are read every 12 ticks while a request runs or a wire reaches their input, one with no wire once a second. Each read is charged to the builder's team (D44), and a team whose share is used up has its builders read later. Builders past the team's limit (D45) are not on the timer: they show the limit error from the moment they start to wait, and the oldest takes a place by direct call when one comes free or the limit is raised. When a limit or the rate of a team's share of server time changes (`set_limits`, `clear_limits`, or a map setting a player changes), what waited on the old value looks again at once (`limit_changes.lua`): projects held at the capacity gate, builders over the limit, and the team's line of projects and its builders waiting for the old share. A script's change of a builder limit is noticed at the timer's next run.
- Only a remote caller's real growth or stamp off charted land asks the game to generate map, and waits for it. The one other place is the hidden lab surfaces: registering a design makes the few chunks its calibration and picture need, charged to the team (D44). Nothing else a player starts (growing from the window, a plan, a blueprint builder) and no plan from anyone ever asks for map: a chunk that does not exist yet closes the spot as uncharted (D43).
- Every team's work is charged to the team (D44): checks, stamps, planned copies, builder reads and requests, updates in place, and registering designs cost estimated microseconds against an account that refills at `seb-work-per-force` per tick. Work may overdraw it once, so nothing is too big to run; the team then waits (projects at a `busy` gate, builders read later), so one team's load slows its own growth first. While the share is used up, the team's projects wait in a line and take turns when it is back, so the first one queued cannot take it all. Every spot tried pays for what it did, however far it got (work.lua): a fixed part, the footprint chunks its checks walk, its probes, the parts and Keep clear tiles it checked (more for a part with something in its way, whose obstacle is looked up), and a stamp's fixed part and parts. A pool's step stops before its next design once the share is used up or it has done the work of checking one design at the part cap; the socket keeps where it got to, and the project goes on from there at its next turn (a turn runs each project in the line once). All teams together get at most `seb-work-per-tick` (default 4000 µs, so up to about 24 ms of work per run of the queue, which comes every six ticks), in turns by the server time each has had (`server_budget.lua`): the account holds one run of the queue's worth and never carries a debt, so one team's big piece is its own debt and the others wait at most for the next run.

### Forces and surfaces

- Everything is keyed by force index and surface index. Nothing assumes the force named "player"; Constructron and Planet Linox both do.
- Force changes, force merges and surface deletion clean up projects and instances.
- The calibration lab is hidden from every force, including forces created later, so it never shows in remote view's surface list.
- Space platforms need no chunk generation. The foundation tiles must be part of the design, and the hub supplies the items.

### Sharing a server

On a Multi-Team Support server every team shares one save, one tick and one map generator. The griefing review (2026-10-26) measured how one team's player could hurt the others: a builder's Stamp grid far off the map queued half a million chunks in 20 seconds (3 GB of RAM); a design with a part far from its blueprint origin generated a million lab chunks in one 8-second tick; Sense, Find and Capture on a self-clocking builder cost 10 to 100 ms per tick each; plans, stopped projects, retired copies and captured designs were never forgotten; a builder's Find crashed the server when its team was released. The rule since: a team's work is limited and charged to the team, so a team's load slows its own growth first and no team can slow the game for the others for long. The last bullet lists what is still one piece in one tick.

- Map: D43 (section 8). Builders keep to charted land unless `seb-builders-charted-only` is off (any generated land then); a headless server charts only while a player is connected, and charted land stays charted (spike S8). Registering a design makes the lab chunks its calibration and picture need (about 390 for a sparse 512-tile design, about 50 bytes each in the save); they stay.
- Time: D44 (section 8). Find, Stamp, Sense, Upgrade and Clear work through a request a piece per read; a Stamp grid places its copies over several reads.
- Size (D45): a design holds at most `seb-max-design-parts` parts and reaches at most 512 tiles across, and is calibrated around itself, not its blueprint origin; a team keeps at most `seb-max-designs-per-force` designs, `seb-max-plans-per-force` plans (a new one replaces the oldest), `seb-max-projects-per-force` live projects and `seb-max-builders-per-force` working builders; copies in flight, its projects' and its builders' stamps together, stop at `seb-max-building-per-force`. Ended projects (stopped, or finished for real) past the newest 30 by id are forgotten with every mark they drew (`set_limits` key `ended_projects`), and so is a retired copy once nothing grows from it. Gallery cells are reused. A book added in the window registers a few designs per run of the due-tick queue, while the team's share lasts; it holds at most 1,000 children and adds at most 250,000 parts, a library holds at most 30,000 designs, and a design has at most 64 drawn sockets and 1,000 electric poles.
- Every limit but the 30 ended projects kept is a map setting, and the remote interface can override any of them for one force (`set_limits`), for an admin who trusts one team more, or a scenario.
- Still trusted: the remote interface (other mods and admins; its functions take ids without checking the force), and the AI Agent Bridge, which passes along a force the agent itself names, so its write tools stay an admin's opt-in.
- Not bounded: a piece of work runs in one tick and is charged after it ran, so it can make that tick long before its team waits it out. Registering a design at the 5,000-part limit took 0.62 to 0.96 s in one tick (headless, on a heavily loaded machine); one stamp of 4,900 ordinary parts pastes in 14 to 24 ms (electric poles cost more per part, so a design may have only so many: D50). Adding a book walks it and copies its blueprints in the tick of the click: the click is turned away while the team's share is used up, the walk is charged, and library blueprints past the first 2,000 parts are read one run at a time. The lab chunks a design needs stay in the save. Removing copies and the overlay's redraws are not charged.

### File layout

Small files, grouped by concern (as shipped in 0.2; the v0.1 proposal had designs.lua and sockets.lua, which became library.lua, prepare.lua and placement.lua):

```
control.lua                      event wiring only
scripts/lifecycle.lua            init, load, configuration changes; migrations.lua upgrades saves; limit_changes.lua
                                 what waited on a limit looks again when it changes
scripts/const.lua                names, reasons and timings
scripts/core/registry.lua        storage schema and ids
scripts/core/library.lua         designs and versions; prepare.lua reads a blueprint (parts, markers, bounds, cost)
scripts/core/books.lua           blueprint books and pools; stale.lua prepares designs again after a mod change
scripts/core/calibration.lua     hidden-surface offsets; labs.lua the lab surfaces; gallery.lua design pictures
scripts/core/placement.lua       the placement transform, sockets, footprints; footprints.lua the overlap index
scripts/core/checks.lua          terrain and obstacle checks; probes, sensors, pools, signals: marker settings
                                 (under.lua: what stands under a copy's parts; cliffs.lua: cliffs under them)
scripts/core/stamp.lua           all-or-nothing stamping; ghosts.lua and tracking.lua tags, recounts, completion
scripts/core/instances.lua       copy states, stalls, retirement; copy_events.lua what a copy's end means for its project
scripts/core/depletion.lua       ore watching and dry drills; update.lua and research.lua updates in place
                                 (update_match and update_vote: where and what of it stands; update_places: their
                                 keys; update_fit: may it be built; update_queue: many copies a few at a time)
scripts/core/forgetting.lua      forgetting retired copies; resources.lua counts the ground's resources for depletion
scripts/core/projects.lua        projects; loop, frontier, growth and gates the growth loop (holds.lua what waits;
                                 spots.lua a spot on the map; walk.lua a socket's designs in turn); plan.lua dry runs
scripts/core/pace.lua            what a step costs, and the team's line for its share (work.lua: the one estimate of
                                 what trying a spot did); retention.lua what a team keeps
scripts/core/budget.lua          each team's share of server time; server_budget.lua the whole server's, in turns;
                                 limits.lua each team's limits
scripts/core/status.lua          what a project says; history.lua its recent history; scheduler.lua the due-tick queue
scripts/circuit/                 the builder: builder, frame, verbs, answer, roster (builders at work), flight (copies
                                 in flight), and verbs/ with one file per verb (sweep.lua: an area a piece at a time; grow_report.lua
                                 what a running Grow shows)
scripts/gui/                     window (a list of designs, a page per design), designs, grow, projects, copies, builder, help, picture cards, outlines (a project hovered or located); book_queue
scripts/render/overlay.lua       marks on the map: a copy's here, a project's in marks.lua, draw.lua what they share
scripts/remote/                  interface, designs, lookup, args, events; agent and agent_write for AI Agent Bridge
scripts/compat/                  mts.lua, ltr.lua
scripts/tool.lua                 growing from the map: the design in hand (grow_cursor.lua) and the area tool; cursor.lua, markers.lua, marker_tools.lua (the Ore sensor and Keep clear tools) and locate.lua beside it
prototypes/                      markers, builder, signals, tools, tips and their simulations
```

### info.json

As shipped in 0.2.0 (the v0.1 draft had the same fields at 0.1.0, with a 310-character summary):

```json
{
  "name": "self-expanding-blueprints",
  "version": "0.2.0",
  "title": "Self-Expanding Blueprints",
  "author": "bits-orio",
  "factorio_version": "2.1",
  "dependencies": [
    "base >= 2.1",
    "? space-age",
    "? multi-team-support",
    "? land-title-registry"
  ],
  "description": "Grow a self-expanding factory from your own blueprints. Draw arrows where the next piece attaches, and robots keep stamping copies until water, cliffs or your rules stop them. Every copy reports when it is done and can be updated or removed exactly. A Recursive Blueprints alternative with readable circuit control; Multi-Team Support optional."
}
```

The description is the portal summary, 344 characters. It leads with what the mod does and carries "self-expanding factory", "blueprints", "robots", "circuit" and "Recursive Blueprints". Re-measure the ranks right after the first sync.

---

## 6. Interfaces and integration

### Remote interface `self-expanding-blueprints` (draft)

Stable from v1 once published.

| Function | Returns | Purpose |
|---|---|---|
| `register_design(force, blueprint_string, name)` | design id | Add a design from a string |
| `list_designs(force)` | array | Ids, names and versions |
| `stamp(params)` | instance id, or nil and a reason | Force, surface, design, position or build position, direction, charted only, materials (parameters: open, no runtime API) |
| `clear(params)` | count | Area deconstruction with filters (v0.2 returns how many entities it ordered, not a job id; the builder's Clear verb waits for them) |
| `remove_instance(instance_id)` | ok, reason | Exact removal |
| `get_instance(instance_id)` | table | State, reason, ghosts left |
| `start_project(params)` | project id | Seed design, surface, place, rules, gates; `retire_depleted` |
| `get_project(project_id)` | table | State, open and blocked sockets, why it is stuck (`status`), `history` |
| `pause_project(project_id)`, `resume_project(project_id)` | true if the state changed | Pause and resume growth |
| `stop_project(project_id)` | true if the project exists | Stop growth; copies built stay |
| `get_event_id(name)` | uint | Event ids, resolved in `on_init` and `on_load` |
| `set_limits(force, limits)`, `get_limits(force)`, `clear_limits(force)` | true, or the limits | One force's own values for the per-team limits (D45) |
| v0.2 also | | `list_pools`, `export_library`, `update_instance`, `update_project`, `build_project`, `set_upgrade_research`, and the AI Agent Bridge tools (read, and opt-in write); [docs/remote-interface.md](docs/remote-interface.md) has them all |

Custom events: `on_instance_completed`, `on_instance_blocked`, `on_instance_stalled`, `on_instance_retired`, `on_project_finished`, `on_materials_missing`.

Planet Linox is the yardstick. It drives Recursive Blueprints+ from an 88-entity controller, 26 of them combinators, to swap which product a 16x16 cell builds by stock level. What it lacked maps onto this interface: job ids, events for built, blocked and missing materials, a library other mods can register into, an anchor chosen per call, and force awareness.

### Multi-Team Support

Libraries, projects and caps are per force, so per team. Team lifecycle events from `mts-v1`, with ids fetched each session, clean up a disbanded team's projects. Admins get map settings for active projects and ghosts in flight per team. v0.2: `seb-max-projects-per-force`, `seb-max-building-per-force` (copies in flight) and `seb-idle-robot-share` (D35); since the griefing review also plans, designs, parts per design, builders, builders on charted land only, and each team's share of server time (D43-D45, "Sharing a server"), with per-force overrides through `set_limits`.

Implemented in v0.1 (`scripts/compat/mts.lua`): Multi-Team Support recycles team forces, so a released team's force keeps its index and passes to the next team. On `on_team_released` (payload `force_name`), the mod drops that force's designs, projects and instance records, so nothing carries over to the next team. Built entities stay in the world. It does not hook `on_force_reset`, which also fires when an admin only resets research. Design ids are unique across forces, so an id a player still holds can never name another team's design, and a player who changes force loses their chosen design and the grow tool.

### Brave New MTS

Everything works from remote view and nothing has to be put into a chest, so growth projects fit a game where robots are the only hands.

### Land Title Registry

The calibration lab is excluded with `set_surface_enabled(lab, false)` when the mod is present, so no blockers or grid land on it. The first plan, a check of every cell under a footprint with `get_cell` and `get_cell_size`, was dropped for the engine's own check (next paragraph).

v0.2 settles the open point by leaving it to the engine: the registry's blocker entities collide with whatever a cell's state does not permit, and the per-part placement check sees them, so a stamp is refused whole before anything is built. The mod only names the reason "outside held land" when a blocker is in a part's way. The gallery lab is excluded like the calibration lab.

### AI Agent Bridge

This mod declares a read tool ("why is this project stuck?") in its own `agent_tools_v1` manifest, so AI Agent Bridge stays mod-agnostic. Write tools ("start a solar project south of the smelters") are opt-in. v0.2 declares three read tools on its remote interface: `seb_projects`, `seb_project` and `seb_designs`; and, only while an admin turns on the map setting `seb-agent-write-tools`, four write tools for the asking player's team: `seb_grow`, `seb_pause_project`, `seb_resume_project` and `seb_stop_project`.

### Blueprint Primer

Primed designs keep their exact item requests through `build_blueprint`, so stamped cells start already supplied. The integration tests stamp a primed design and check its requests.

### Negative Space

A design blueprinted while Negative Space is active can carry its markers. Negative Space acts only on a player's own paste, and its marker items cannot be crafted, so read as ordinary parts they would put an item nobody has in the bill of materials and leave ghosts nothing builds. v0.2 reads them as markers instead (const.FOREIGN_MARKERS): the plain one is a Keep clear tile, the automatic ones around belts and pipes are left out (their direction-aware logic lives in Negative Space). Its ghosts are removed from our stamps like our own markers (D41).

### Space Age

Planets work like Nauvis. Space platforms grow from their hub, with the foundation in the design (§5). v0.2 (D34): on a platform the hub's inventory is the supply the materials gate counts and the hub builds the ghosts; there are no robots to wait for, so no spot is ever parked as out of reach. Tested headless under Space Age.

---

## 7. Competitive landscape

Studied on 2026-10-25 by reading each mod's code; download counts are from that day. No mod on the portal tracks a stamp's own ghosts to learn when it is finished. Every earlier answer polls an area or watches a stand-in.

Local copies of every mod's code, its portal metadata and the saved Recursive Blueprints+ discussion threads are in `reference/`, indexed by `reference/README.md`. The folder is git-ignored: two of these licences forbid republishing.

| Mod | Author | Factorio | Downloads | What it does | What this design takes |
|---|---|---|---|---|---|
| Recursive Blueprints+ | FoxLBA | 2.1 | 39,815 | Numbered circuit commands on a one-slot chest; area scanner | The capability checklist |
| Recursive Blueprints | DaveMcW | 1.1 | 30,603 | The original: deploy, deconstruct, copy | A small core |
| Simple Recursive Blueprints | Qweasd123tg | 2.1 | 13 | One marker arrow repeats a blueprint in a line | Anchor transform and tests (S1); arming flow (S2) |
| Recursive Blueprints Extended | realvictorprm | 0.16 | 10 | The original plus an area checker for unfinished ghosts | Evidence that completion has been the pain since 2018 |
| PersistantBlueprints | mrvn | 0.17 | 11 | Copies linked to a master area, edits propagated | Diff updates; the link kept in combinator signals |
| blueprint-deconstruction-markers | Elwin | 2.1 | 53 | A marker that clears its tile on superforce | Destroying marker ghosts on creation |
| Negative Space | Rycieos | 2.1 | 699 | Empty-space markers, auto-added around belts and pipes | The mirroring marker, simulations, undo handling |
| Blueprint Variables | BinarySpike | 1.1 | 4,849 | Variables in blueprints, set on paste | Parameters applied as entities are built |
| Construction Probe | Eketek | 2.0 | 343 | Construction costs as circuit pulses | The bill-of-materials output; a transient tick handler |
| Constructron-Continued | ILLISIS | 2.1 | 43,266 | Spidertrons build anywhere | Recount instead of decrement; stall deadlines |
| AutoDeconstruct | mindmix | 2.1 | 367,142 | Retires drills when their ore runs out | The depletion pipeline; re-registering in `on_load` |
| concreep-redux | utoxin | 2.1 | 5,353 | Roboports tile floors outward | Gates on idle robots and stock |
| Train Scaling | shanemadden | 1.1 | 5,938 | Trains built from templates on demand | Plan-then-commit materials; refunds on abort |
| Planet Linox | Xeon257 | 2.1 | 15,675 | A planet whose core loop runs on Recursive Blueprints+ | The remote interface a content mod needs |
| Mining Patch Planner | rimbas | 2.1 | 174,848 | Drill layouts for a selected patch | Time-sliced work; it has no remote interface to call |
| Oil Outpost Planner | Coppermine | 2.1 | 30,754 | Oil outpost layouts | It has no layout API to call |
| AutoPrint | ed_mercer | 2.1 | 324 | Generates a factory blueprint on a hidden lab surface | The hidden-surface technique; a source of designs |
| Blueprint Evolution | Skybeach88 | 1.1 | 137 | Random and mutated blueprints for Recursive Blueprints | An idea for later |

---

## 8. Scope, roadmap and decision log

### v0.1 slice

- Named designs per force.
- Grow with implicit edge sockets, plus one drawn socket type that targets the same design or a named design.
- Ghost-tag tracking with recount, and completion-driven growth.
- Stop rules for water, cliffs and a count, and the materials gate.
- The overlay with states.

Acceptance test: a solar design with sockets east and south fills a region and stops at water. Retiring one instance removes exactly its entities and nothing next to them.

### Later milestones

**Open:** the order.

- ~~Probes and pools~~ (v0.2); ~~the project window~~ (v0.2: projects list with status and history, and a copies panel with locate, update and remove).
- ~~The circuit builder: Stamp, Clear, Remove and Sense; the handshake; errors; status outputs~~ (v0.2).
- The remote interface made stable (still a draft, ADR-0007); ~~Land Title Registry's held-land rule~~ (v0.2, by the engine's own check).
- ~~Retirement on depletion~~ (v0.2, with ore sensors); ~~update in place~~; ~~research-driven upgrades~~ (v0.2).
- ~~Find, grid stamps, ports with Read and Write, Capture~~ (v0.2); parameters (open: no runtime API).
- ~~Space platforms~~ (v0.2); ~~Tips and Tricks simulations~~ (v0.2, 21 entries); ~~the AI Agent Bridge read tool~~ (v0.2); ~~a seed-only challenge scenario~~ (v0.2, `scenarios/seed-only`).

### Spikes

Run in-game before building on them.

| Spike | Question |
|---|---|
| S1 Placement | Does the entry arrow land exactly on the socket for even, odd and rotated designs? Calibration surface against Simple Recursive Blueprints' transform; flips |
| S2 Marker settings | Do marker settings survive library edits, books, copy-paste and select-new-contents? Blueprint entity tags against native combinator signals |
| S3 Tracking coverage | Do tags arrive on every build path: player, robot, platform, script revive? Tile ghosts by position; item-request-proxies |
| S4 Update in place | Can copies be updated without losing machine contents (Wube forum topic 130518)? Diff against re-stamp |
| S5 UPS | What do `build_blueprint` and recounts cost for a few hundred stamps of a large design? Should one stamp spread over several ticks? |
| S6 Registration | What does registering a design cost, and what limit keeps a circuit Capture from freezing a multiplayer game? (Run: about 35 µs per floor tile; Capture held to 64 x 64 tiles) |
| S8 Charting | Can tests and a server with nobody online rely on `LuaForce.chart` and `is_chunk_charted`? (Run: nothing is charted while no player is connected; charted land stays charted) |

### Decision log

| # | Date | Decision |
|---|---|---|
| D1 | 2026-10-26 | Name: Self-Expanding Blueprints, internal name `self-expanding-blueprints` (§1) |
| D2 | 2026-10-25 | At least as powerful as Recursive Blueprints+; the checklist in §4 is binding |
| D3 | 2026-10-25 | No magic numbers, no packed numbers, no signal with two meanings, no map setting that changes meaning |
| D4 | 2026-10-25 | Circuits can drive everything, through named verbs and a request, ACK, DONE handshake |
| D5 | 2026-10-25 | Recursion is drawn into designs as sockets; circuit-driven recursion works too |
| D6 | 2026-10-25 | Designs are referenced by number or name from a library, never copied between chests |
| D7 | 2026-10-25 | Stamps are tracked instances; completion comes from event hints plus a recount, never a decrementing counter |
| D8 | 2026-10-25 | Stamps are all or nothing |
| D9 | 2026-10-25 | Keyed by force and surface; nothing assumes the force "player" |
| D10 | 2026-10-25 | Event-driven; no unconditional `on_tick` |
| D11 | 2026-10-25 | Written from scratch; not a fork of any mod |
| D12 | 2026-10-25 | Parameters and instance-addressed Read and Write stay; an earlier draft had cut them |
| D13 | 2026-10-26 | Markers are constant combinators; a socket names its target design in its description (ADR-0001) |
| D14 | 2026-10-26 | Stamps land by calibrating a stamping copy with snapping cleared and an anchor added (ADR-0002) |
| D15 | 2026-10-26 | A stamp that comes out short is rolled back (ADR-0003) |
| D16 | 2026-10-26 | The remote interface ships in v0.1 as a draft, for the tests (ADR-0007) |
| D17 | 2026-10-26 | The prototype and signal prefix stays `seb` |
| D18 | 2026-10-26 | A socket's child without an entry arrow attaches by the middle of its back edge; remote stamps and seeds without one keep the vanilla anchor (ADR-0006) |
| D19 | 2026-10-26 | Designs are versioned snapshots in a script inventory; a failed update changes nothing; design ids are unique across forces (ADR-0009) |
| D20 | 2026-10-26 | Six instance states with events; a stall says why (ADR-0010) |
| D21 | 2026-10-26 | Gates hold the head of the frontier; a socket no robots reach is parked and retried (ADR-0011) |
| D22 | 2026-10-26 | The window lists projects in v0.1, updated in place (ADR-0012) |
| D23 | 2026-10-26 | Blueprint grid settings are honoured as they are: relative snapping steps by the grid, absolute snapping also keeps the world grid; no Spacing field; staggering is drawn with socket arrows (ADR-0006) |
| D24 | 2026-10-26 | Players see the entry arrow as the Plug; prototype and code names stay `seb-entry`/entry, so drawn blueprints keep working. Marker buttons carry captions and a help panel explains both with a diagram |
| D25 | 2026-10-26 | Stopping a project removes every mark it drew, its copies' outlines included; copies stay and robots finish the ones under construction |
| D26 | 2026-10-26 | A project reports a status level and keeps a ten-entry history of notable events, repeats merged; the capacity gate is pacing, not waiting |
| D27 | 2026-10-26 | Design pictures come from a copy of each design built as ghosts of its force on the hidden surface `seb-gallery`, shown through a camera |
| D28 | 2026-10-26 | Ore sensors gate when a copy's sockets open (drill area, a radius signal R, or one tile); retirement on depletion is a project option |
| D29 | 2026-10-26 | The blueprint builder: a decider body with a hidden constant combinator driving its output; one input (red and green summed); one request at a time; read every 12 ticks (ADR-0015) |
| D30 | 2026-10-26 | A probe's predicate comes from its signals: resources by entity, item or fluid; water; "deny" negates |
| D31 | 2026-10-26 | A labelled book is a pool under its label; a socket naming it tries the book's designs in order (ADR-0016) |
| D32 | 2026-10-26 | Update in place lays the new version over the copy by voting on shared parts, builds it superforced, and refuses over anyone else's building (ADR-0017) |
| D33 | 2026-10-26 | Dry runs run every check, place no ghost, stop at 400 copies, and are built as a new project with the same start (ADR-0016) |
| D34 | 2026-10-26 | On a space platform the hub's inventory is the supply and nothing is parked for robots |
| D35 | 2026-10-26 | Admin caps are map settings: projects per force, copies in flight per force, a share of idle robots |
| D36 | 2026-10-26 | Help is a draggable window beside the main one, with a picture per marker; Tips and Tricks keeps the long form with live examples, reached from each tab through a [tip] link put in the player's chat (no API opens Tips and Tricks, and a [tip] link opens it only from chat, not from a GUI label; a mod window cannot be resized) |
| D37 | 2026-10-26 | A project's first copy is stamped even where no robots reach yet; later copies wait (parked) for robots |
| D38 | 2026-10-26 | Copies under construction show where growth goes next: socket arrows and dashed outlines of the next copies |
| D39 | 2026-10-26 | Superforce is a Grow option for real growth and plans alike (buildings in the way are marked for removal); trees and rocks are always cleared |
| D40 | 2026-10-26 | A plan may paste its first copies (up to 20) as look-only ghosts of the neutral force: only the parts that fit go down and nothing in the way is cleared; no robots serve that force, so they are never built; they go when the plan is built or stopped, and give way to any copy stamped or planned over them |
| D41 | 2026-10-26 | A Keep clear marker: a tile the design needs empty counts in the footprint, is cleared of trees and rocks, and refuses a building (removed when superforced); Negative Space's plain marker reads as Keep clear, its automatic ones are left out |
| D42 | 2026-10-26 | Markers are points (empty collision box, tile size 1), so other mods' ground rules that measure a building's box leave them alone; the pre-check mirrors no rules of mods the mod does not integrate with |
| D43 | 2026-10-26 | Nothing a player starts makes the game generate map (registering a design makes only its few hidden lab chunks, charged to the team): plans never do, builders keep to charted land (a map setting allows any generated land), and only a remote caller's real growth or stamp off charted land requests chunks |
| D44 | 2026-10-26 | Each team's work is charged in estimated microseconds to an account refilled at a per-team rate; work may overdraw it once, then the team waits, so a team's load is paid for by its own growth (a piece of work is charged after it ran and is never split, so it can still make one tick long); a server-wide account (`seb-work-per-tick`) caps all teams together, taken in turns, with no debt |
| D45 | 2026-10-26 | Per-team limits are map settings with per-force overrides (`set_limits`): projects, plans (the oldest gives way), designs, parts per design, builders, copies in flight; ended projects past 30 and retired copies nothing grows from are forgotten; designs are calibrated around themselves and reach at most 512 tiles |
| D46 | 2026-10-27 | A server-wide cap on the mod's work, `seb-work-per-tick` (default 4000 µs, 0 = off), is shared by the teams in turns, each within its own share; there is no server-wide debt, so one team's big piece is charged to that team only |
| D47 | 2026-10-27 | Updating many copies to a new version (a project's update, a research upgrade, `update_project`) is queued and made a few copies per run of the due-tick queue while the team's share allows; one copy's update is one piece, bounded by the design's parts and charged to the team |
| D48 | 2026-10-27 | Only a cliff under a part (an entity's collision box, a design tile) or under a Keep clear tile stops a copy; with cliff explosives researched it is blown up instead: the stamp orders it removed, the materials gate waits for one explosive per cliff, a plan counts the spot as fitting, and a stamp rolled back takes the orders back |
| D49 | 2026-10-27 | A design draws at most 64 sockets, refused when it is registered (`too-many-sockets`); the size limits apply when a design or version is registered, never when it is prepared again; a book walk looks at most at 1,000 children and a book adds at most 250,000 parts, its library records past the first 2,000 parts read one run at a time (a record stays readable from a stored reference, measured in multiplayer), a library holds at most 30,000 designs, and the overlay draws at most 100 open-socket arrows per project |
| D50 | 2026-10-27 | A design has at most 1,000 electric poles, refused when it is registered (`too-many-poles`): a pole's ghost wires itself to every pole in reach, so a carpet of poles one a tile costs more the bigger it is. Measured, stamp and registration: 250 poles 3 and 13 ms, 500 8 and 37 ms, 1,000 28 and 122 ms (about what the biggest design without poles takes), 2,000 127 and 450 ms, 4,900 546 ms and 2.4 s, where 4,900 chests stamp in 16 ms. The cap was 250 first and raised once measured; it limits one design, never a base. Poles are charged 40 µs a paste (`COST.pole`) and 100 µs at registration (five pastes). Pasting a copy in slices over several ticks was weighed and set aside: it would end all-or-nothing stamps (ADR-0003) and cut the wires between slices |
| D51 | 2026-10-27 | A paste turned or flipped in hand turns or flips the whole project: its copies, and by default its grow-toward directions (an option keeps them to the world). The engine flips a blueprint only in a player's hand, so a flipped paste grows the design's mirror twin: a hidden design drawn part by part (`mirror.lua`: x negated, facings mirrored, splitter sides swapped, the engine's mirror flag toggled; it matched the engine's own flip for fluid machines, inserters, belts, undergrounds, splitters, pumps, combinators, drills, boilers), remade with each new version, deleted with the design, its projects shown under the design. A horizontal flip is the twin facing the same way, a vertical one the twin half a turn further; a blueprint that snaps to a grid turns over inside its grid cell, absolute or relative (all measured against the engine's flips). Rails, signals, stops and wagons are refused: they cannot be turned over part by part. Teaching designs to flip in place (8 facings) was weighed and set aside: it touches every part that turns a design |
| D52 | 2026-10-27 | Water is any floor with the `water_tile` layer: Nauvis water, Gleba's wetlands and lake, Vulcanus lava, Fulgora's oil ocean, Aquilo's ammoniacal ocean and brash ice, and space. A copy stands on it only on its design's own floor, or where its project superforces (Replace buildings in the way, the remote `superforce`, a Ctrl + Shift paste of the design from the hand): then the engine lays that floor's cover tile there (landfill, foundation, ice platform, platform foundation), the materials gate counts those items, and an update in place lays it only for a superforcing project's copies. Anywhere else water closes the socket as `water` ("Blocked by water, lava or space"), the cover researched or not; `landfill = false` still refuses any water. Measured on 2.1.23: forced and superforced `build_blueprint` both cover, normal never; what turns it on is an enabled recipe that makes the cover tile's item and is not hidden, not the technology (researched with its recipe disabled covers nothing; a hidden or recycling recipe making landfill covers nothing; another visible one does). The cover goes where the floor keeps a part off: the tiles of its collision box its collision mask meets (a small pole 1, a solar panel 9, a straight rail 4, two poles 5 tiles apart 2), and the tiles of its tile rules' areas the floor fails (in open water an offshore pump's own tile, 1, a rail ramp's foot, 16; a pump at a shore gets none; on Gleba's wetland only a rail support stands without cover); and under a design tile that can go on the cover, which stacks on it, the copy counting that tile once, as the one on top (stone path goes on landfill and foundation, not on ice platform, which melts, nor on platform foundation, which takes no tile). The engine completes a design's own landfill that covers part of a part; without the recipe nothing is laid, paving included; `LuaSurface.set_default_cover_tile` did not change what `build_blueprint` lays. Run through the mod on every Space Age floor: a plain copy closes `water` and lays nothing, a superforced one waits for 9 of the right item and completes on it, and without the recipe closes `water`; `out-of-map` and `water-wube` have no cover and close `water` either way. A forced check that passes over water says the engine covers it; tiles have no such check, so their recipes are looked up. Water is looked for once over a footprint (1 µs plus 5 ns a tile, charged as `water_tile`), under each part only when the footprint holds some, and part by part for a footprint of more than 200 tiles a part |
| D53 | 2026-10-27 | A socket whose child would stand on the copy it grows from waits, instead of closing as `overlaps-parent`, while that copy is going for depletion and nothing else is in the way. Going means it is being removed for depletion, or its project retires depleted copies (its drills are watched) and they have run dry, or its sensors see no ore left. The socket leaves the frontier on its own, so the project's other sockets go on (`awaiting` in `get_project`, `parent-retiring` on the map and in the row once nothing else happens), and goes back when the copy's retirement ends (`instances.hooks.retired`), not on a timer. So a design can lay a different piece on its miner's ground: a creeping drill whose socket on its own ground names a belt piece leaves a belt line behind it, from two designs, where belts and poles may not stand on ore. Without `retire_depleted` the copy never goes and the socket closes as before. A plan mines nothing, so it plans the piece over a copy with drills and sensors (`depletion.mined_out_goes`, `prepared.drill_count`). Holding the whole project at the socket, as the other gates do, was set aside: a field of creeping lines would move one line at a time. A miner cannot be rebuilt on its own ground for ever: a drill's ghost needs ore under its body (measured on 2.1.23: the forced blueprint-ghost check refuses a drill with ore only in the ring of its mining area), and the copy went because nothing its drills could mine was left there, so such a socket closes as `no-resource` |
| D54 | 2026-10-28 | With "Replace buildings in the way" (a project's `superforce`: the window option, the remote `superforce`, a Ctrl + Shift paste of the design, the builder's Superforce on Grow) a copy may grow over the copy it grows from. When that copy is the only one in the way, the spot goes on to the map checks, and the superforced stamp treats its parts in the way like any of the force's own buildings: they are marked for removal and the child is built. A part whose twin already stands there (same name, place and facing) gets no ghost from a superforced paste and is left as it is (measured on 2.1.23); the stamp counts it as placed, so the copy is whole, and that entity stays its owner's. The parent loses the parts the robots take, stays complete and is not rebuilt; its footprint and the child's overlap in the index, and removing it later takes only what it still has. So one blueprint creeps: three belts carrying west and a pole at the back, a drill in front with an ore sensor, a plug at the back and a socket on the drill's first column pointing away, naming the design itself. Once the drill's ore is gone the next copy lands a drill's length on, its belts and pole replacing the old drill and its drill on fresh ore, and the old copy keeps its belts and pole. Nothing is removed for running dry unless asked: "Remove copies whose ore runs out" stays whole-copy removal (opt-in, D28), and Keep clear tiles stay the way to ask for ground to be cleared; with both options on, a parent whose drill look comes before the robots take its drill still goes whole. Another copy in the way still closes the socket as joined, and without superforce D53 stands (overlaps-parent, or the wait under `retire_depleted`). A plan with superforce plans the child over its planned parent. Removing only a mined-out copy's drills under `retire_depleted` was weighed and set aside: nothing should go for running dry unless the player asks |
| D55 | 2026-10-28 | A copy with nothing of it left is released: when one of its entities goes (any way but its own retirement), it is recounted, and with no entity of it standing and no ghost or item request of it waiting it is retired on the spot, removing nothing (its tiles stay), so its footprint frees and `on_instance_retired` is raised. A copy that placed no entity (tiles only) and one being updated are never released this way. Saves from before it recount every such copy once on load. Players remove buildings by hand, and a copy holding an empty spot refused every paste there; recounting QUIET_TICKS after the event lets an upgrade or fast-replace, whose replacement is built in the same tick, keep its copy. |
| D56 | 2026-10-28 | The materials gate, its robots-busy share and a stalled copy's reason count every roboport network reaching the spot, summed; a personal roboport (a network of one mobile cell, holding its player's inventory) counts only where no roboport network reaches. Measured on 2.1.23: `find_logistic_networks_by_construction_area` lists a character's personal roboport among the others, with the player's inventory as its items. Picking the network with the most idle robots let a player standing by a project with a personal roboport decide the gate from their pockets ("needs 2, the network can spare 1" while the base held 20). |
| D57 | 2026-10-28 | Grow is for spamming projects: the design comes back into the hand the tick after each click (the click itself must leave it empty to call the engine's paste off), so every click starts a project; Grow and Fill an area leave the window open. The engine keeps no turn or flip for a blueprint put into the hand by script, so the hand is refilled turned and flipped as the last paste had it (its parts turned in quarter turns, its mirror twin for a flip; a snapped blueprint refills unturned, its grid would turn too), and the next paste's own turn and flip go on top. Measured on 2.1.23: with the button held, the engine pastes the refilled blueprint again every 6 ticks at the same spot, so a paste where the last one was within 15 ticks is the same click; and a project not yet stamped holds its seed's spot (`seed_box`), so a quick second click cannot start one on top of it. Projects and designs per team are unlimited by default (map settings; 0 = no limit), at the author's call. |

### Open questions

- ~~The builder's name, its data wiring and its request queue depth (§4).~~ Decided: D29, the blueprint builder; one input, red and green summed; one request at a time.
- ~~Whether sockets can open before their instance completes (§2).~~ Decided: as an option, `open_early` (v0.2).
- Parameters: rewrite a copy before stamping, as Recursive Blueprints+ does, or apply them to ghosts and built entities, as Blueprint Variables does.
- ~~The marker prototype and where marker settings live (§5, S2).~~ Decided: D13, ADR-0001.
- Flips in v1 (§5, S1).
- ~~Short stamps: mark them incomplete or roll them back (§5).~~ Decided: roll back, D15, ADR-0003.
- ~~The Land Title Registry state each design needs (§6).~~ Decided in v0.2: left to the engine; the registry's blockers refuse a stamp whole (§6).
- ~~Library export and import between saves (§2).~~ Decided: one blueprint book from the window's book button or `export_library`; adding it in another save registers each design (v0.2).
- Undo for player-started stamps (§3).
- A separate add-on that speaks Recursive Blueprints+'s protocol (§4).
- Messages to FoxLBA, DaveMcW and Qweasd123tg before release (§1).
- The milestone order after v0.1 (§8).
- Staggered growth (each copy shifted sideways per step): a "Shift" field in the Grow window, or socket arrows only? Socket arrows do it today; vanilla grids cannot express it. To be decided after the author has played v0.1.
- Parameters (per-instance values): no runtime API reads or writes blueprint parameters; a port's Write covers some of the need.
- ~~The prototype and signal name prefix; `seb` is provisional.~~ Decided: D17.
