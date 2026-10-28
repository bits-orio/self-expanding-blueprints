# Remote interface `self-expanding-blueprints` (draft)

Shipped early for the headless tests ([ADR-0007](adr/0007-the-remote-interface-ships-early-as-a-draft.md)). Names and shapes may change before v1, when the interface becomes stable.

```lua
local id, reason = remote.call("self-expanding-blueprints", "stamp", {
  force = "player", surface = "nauvis", design = "Solar cell", position = { 100.5, 40.5 },
})
```

## Arguments

- **force**, **surface**: a `LuaForce` or `LuaSurface`, its name, or its index.
- **design**: a design id (number) or name (string), within the force's library.
- **positions**: `{x = 1, y = 2}` or `{1, 2}`.
- **areas**: `{left =, top =, right =, bottom =}`, `{left_top =, right_bottom =}` or `{{x, y}, {x, y}}`. Rounded outward to whole tiles.
- **directions**: `defines.direction.north`, `east`, `south` or `west`. Diagonals are refused.

Every argument is checked when the call arrives. A bad one returns `nil, "invalid-<field>"` (for example `"invalid-max_instances"`, or `"invalid-point"` for a point off the map: coordinates must lie within +-1,000,000 tiles), and nothing is stored. Params that are not a table return `nil, "invalid-params"`. An unknown force, surface or design returns `"unknown-force"`, `"unknown-surface"` or `"unknown-design"`; so does a force or surface of the wrong kind (a `LuaSurface` given as the force). `list_designs` returns an empty array for an unknown force, and `list_pools` an empty table. A field a function does not read is ignored.

## Where a stamp lands

`stamp` and `start_project` take exactly one place. Giving none, or more than one, returns `"invalid-position"`.

| Field | Meaning | Taken by |
|---|---|---|
| `position` | The design's entry arrow lands on the tile holding this point, facing `direction`. A design without an entry lands by its vanilla blueprint anchor: its footprint is centred on the point, or, for a blueprint with absolute snapping, it takes the world grid cell holding the point. | both |
| `build_position` | The raw build position, used as given. It must be a whole-tile position, and an even one for designs with rails or other 2x2-grid entities, or the call returns `"off-grid"`. | both |
| `point` | The first copy lands as the player's own blueprint would with the cursor there (as a click with the design in hand): its footprint is centred on this point, or, with absolute snapping, it takes the world grid cell holding the point. | `start_project` |
| `area` | Growth fills this area from its top-left corner and never leaves it (the window's Fill an area starts at the corner the drag started from instead); with absolute snapping, from the first placement on the blueprint's grid that fits. | `start_project` |

## Functions

### Designs

| Function | Returns |
|---|---|
| `register_design(force, blueprint, name?)` | for a blueprint: its design id and whether it is new; for a blueprint book: a list of design ids and, for a labelled book, the pool's name; or nil and a reason. `blueprint` is an export string, a blueprint library record (`LuaRecord`, one of `game.blueprints` for example) or an item stack holding a blueprint or book |
| `export_library(force)` | every design of the force as one blueprint book string; or nil and `"unknown-force"` |
| `list_designs(force)` | array of `{id, name, version, icon, ok, error, sockets, has_entry}` in id order; `icon` is a `SignalID` or nil, `sockets` is the number of socket arrows |
| `list_pools(force)` | `{[pool name] = {design id, ...}}`, each list in the pool's order, each design once |
| `set_upgrade_research(force, design, technology?)` | true; or false and a reason |
| `delete_design(force, design)` | true; or false and `"unknown-force"` or `"unknown-design"` (an id or a name; a hidden mirror twin is not one). The design and its mirror twin leave the library, their projects end and are forgotten, and their copies are forgotten: what they built stays in the world, and their ground is free for other copies |

`register_design` with a blueprint: a taken name makes a new version of that design; no name uses the blueprint's label, and a blueprint without one becomes `Design N`. A new blueprint that cannot be stamped is still registered (id and true), and `list_designs` shows it with `ok = false` and its `error` (`many-entries`: more than one entry arrow; `empty-blueprint`: only markers, nothing to build; `calibration-failed`). As an update it returns nil and that reason and changes nothing. A record or stack is registered as it is at the call: editing the record later changes nothing until it is registered again. Other refusals: `"invalid-design"` for a string that is not a blueprint or a book (or an empty stack), `"empty-blueprint"` for a blueprint that is not set up, `"invalid-name"` for a `name` that is given but is not a non-empty string, and `"unknown-force"`. A blueprint wider or taller than 512 tiles, markers included, or with more parts (every entity, markers included, and every tile) than `seb-max-design-parts` allows, is refused with `"design-too-big"` before anything is built, one with more than 64 drawn sockets with `"too-many-sockets"`, and one with more than 1,000 electric poles with `"too-many-poles"`, as a new design or as a new version; these limits apply only when a blueprint is registered, so a design registered before a cap was lowered keeps working. A new design past `seb-max-designs-per-force`, or past 30,000 whatever the setting, is refused with `"too-many-designs"` (a new version never is). Registering is charged to the force's share of server time (`seb-work-per-force`), by its parts, by the hidden lab chunks its calibration and picture need made, and by the length of the blueprint string, refused or not; the call itself is never held back.

`register_design` with a blueprint book (books inside it too) registers every blueprint in it that is set up, each as above under its own label: `name` is ignored. It returns the design ids in book order and, when the book has a label, the pool's name. A pool is those designs, in order and each once (a book holding one design twice lists it once), under the book's label: a socket whose description names the pool tries them in turn and stamps the first that fits, unless a design has that name, which is used instead. Registering the book again replaces the pool. An update that cannot be stamped, and any blueprint refused as above, is left out of the list; when no blueprint is registered it returns nil and the first reason (`"not-a-blueprint"` for a book with no blueprint that is set up). A book whose walk would look at more than 1,000 children, counting empty blueprints, planners and the books inside with what they hold, registers nothing and returns nil and `"book-too-big"`.

`export_library` gives each design as registered (its newest version), labelled with the design's name, in a book labelled `Self-Expanding Blueprints`. Adding that book with `register_design`, in this save or another, registers each blueprint again and, because the book is labelled, makes a pool of that name.

`set_upgrade_research` names the technology whose research moves every outdated copy of the design to its newest version in place, as `update_instance` does; a nil `technology` clears it. Register the better version first. The copies move when the force finishes that research, a few per run of the mod's due-tick queue while the force's share of server time lasts (as `update_project` queues them); naming one it has already researched moves nothing. It returns true, or false and `"unknown-force"`, `"unknown-design"` or `"unknown-technology"`.

### Instances

| Function | Returns |
|---|---|
| `stamp(params)` | instance id; or nil, a reason and, when a place stopped it, a map position (below) |
| `remove_instance(instance_id)` | true; or false and `"unknown-instance"` (no such copy, or one that has retired and been forgotten) or `"already-retiring"`. Removes exactly what that instance built. |
| `get_instance(instance_id)` | `{id, design_id, version, state, reason, ghosts_left, project_id, surface_index, force_index, position, direction, footprint, parent, children, entity_count, sensors, waiting_ore, created_tick, last_progress_tick, ore_check_tick, drill_check_tick}`; nil for an unknown instance, which includes a copy that has retired and been forgotten (see below) |
| `update_instance(instance_id)` | true; or false and a reason |

`stamp` params: force, surface, design, a place, `direction` (default north), `charted_only` (default false), `materials` (default false). It stamps at once, all or nothing, and the copy starts `building`. With `charted_only` false a stamp may land on land the force has not charted, and asks the game to generate chunks that do not exist yet (refused with `chunks` until they do): with `start_project`, the only way anything in the mod makes the game generate map (besides the hidden lab surfaces where a design being registered is measured and pictured). Nothing a player starts (the window, plans, blueprint builders) ever does. A stamp does not wait: with `materials`, a shortage refuses it. A refusal comes with a reason and, for most, a map position:

| Reason | Position | Meaning |
|---|---|---|
| `off-grid` | the position given | the place is off the design's lattice |
| `uncharted` | the chunk's centre | a chunk under the footprint is not charted (`charted_only`), or does not exist yet where the map may not be generated |
| `water`, `cliff`, `building` | the obstacle | water the design's own floor does not cover (superforced: that the force cannot cover yet), where water is any floor with the `water_tile` layer (lava, the oil and ammonia oceans, space and Gleba's wetlands too); a cliff; or something else the build cannot clear (it clears trees and rocks) |
| `held-land` | the obstacle | the Land Title Registry does not let the team build there |
| `no-resource` | the obstacle | a mining drill of the design has no ore under it |
| `probe` | the probe's tile | a probe marker of the design does not hold on its tile |
| `misaligned` | the build position | the entry arrow did not land on its target; the stamp was rolled back |
| `stamp-short` | the build position | fewer entities came out than the design has; the stamp was rolled back |
| `joined` | none | it would overlap another copy |
| `seed-occupied` | none | `start_project` only: the first copy would stand on copies already there |
| `invalid-design` | none | the design cannot be stamped |
| `chunks` | none | the chunks under it are not generated yet (now requested) |
| `no-network` | none | with `materials`: no construction network reaches it (never for a project's first copy, which goes down anyway and waits for robots) |
| `robots-busy` | none | with `materials`: fewer of the network's construction robots are idle than `seb-idle-robot-share` asks |
| `missing-materials` | none | with `materials`: the network cannot spare what the copy costs |

`remove_instance` destroys the instance's unbuilt ghosts and orders its built entities and tiles deconstructed. The instance is `retiring` until the robots are done, then `retired` (`on_instance_retired`). A retired copy's record is forgotten right after `on_instance_retired`, which still names it and still finds the record, so `get_instance` then returns nil and a save does not grow with every copy a team stamps and removes. `parent` and `children` may therefore name copies that are no longer on record. One kind stays on record, as `retired`: a copy retired for depletion (`retire_depleted`) while its project is growing or paused, because growth still parents from it; it is forgotten when the project ends (stops or finishes) or is forgotten. A copy with nothing of it left (every entity of it removed by other means, by hand or by another mod, and no ghost or item request of it waiting) is released the same way without anything being removed: it goes straight to `retired` (`on_instance_retired`), its spot is free, and tiles it laid stay.

`get_instance(...).state` is `building`, `complete`, `incomplete`, `stalled`, `retiring` or `retired`. `reason` explains `stalled` (as for `on_instance_stalled`) and `incomplete` (`ghost-removed`: a ghost vanished unbuilt). `ghosts_left` is what is still to be built, or, while retiring, to be removed. `position` is the build position and `footprint` a box `{left, top, right, bottom}`. `sensors` lists the world areas its ore sensors watch; `waiting_ore` is true while a finished copy waits for that ore to run out before its sockets open. `created_tick` is when it was stamped, and `last_progress_tick` when it last got closer to done: a copy still building stalls three minutes after that. `created_tick` is nil for copies stamped before 0.2. `ore_check_tick` and `drill_check_tick` are the ticks at which a queued look at the copy's ore sensors, or at what its drills can still mine, is due; nil when none is queued. A run of depleted tiles under a copy queues one look of each kind, not one per tile.

`update_instance` moves a copy to its design's newest version in place: parts both versions share stay, new parts come as ghosts, and parts only the old version had are deconstructed. The copy is `building` again until the new ghosts are built, and then raises `on_instance_completed` again. A refusal changes nothing. The update is made in the call and charged to the copy's force (`seb-work-per-force`), refused or not, by its parts, the parts that are new and its footprint's chunks (and, for a copy from an older save that does not record where its parts are, its footprint's tiles); the call itself is never held back. Reasons:

- `unknown-instance`: no such instance, or one that has retired and been forgotten.
- `up-to-date`: the copy already has the newest version.
- `unknown-design`: the design is gone, or the copy is retiring or retired.
- `invalid-design`: the newest version cannot be stamped.
- `misaligned`: the new version cannot be laid over the copy's entities, or would sit off the design's lattice.
- `joined`: the new version would overlap another copy.
- `building`: a building or ghost of any force, not part of this copy, stands under a part the new version adds (or under its tiles or Keep clear tiles).

### Projects

| Function | Returns |
|---|---|
| `start_project(params)` | project id and, for a dry run, a list of the ids of the plans stopped to make room for it (or nil); or nil and a reason |
| `get_project(project_id)` | `{id, state, design_id, surface_index, count, building, open_sockets, parked, awaiting, gate, blocked, closed, stalled, waiting_ore, status, history, nothing_built}`; nil for an unknown or forgotten project |
| `pause_project(project_id)`, `resume_project(project_id)` | true if the state changed (growing to paused, paused to growing) |
| `stop_project(project_id)` | true if the project exists. Its copies stay, robots finish the ones under construction, and a stopped project cannot be resumed. |
| `update_project(project_id)` | how many outdated copies were queued for update, and 0 (two numbers; `0, 0` for an unknown project). The copies are updated as `update_instance` does, a few per run of the mod's due-tick queue while the force's share of server time lasts; a copy already queued is not queued again, and one that retires or is updated meanwhile is passed over. Once the last has had its turn, the project's history gets an `updated` entry with how many were updated and how many refused. |
| `build_project(project_id)` | the new project's id; or nil and a reason |

`start_project` params: force, surface, design, a place and these, all optional:

| Param | Default | Meaning |
|---|---|---|
| `direction` | north | the seed's facing |
| `directions` | east, south | where copies of a design without socket arrows grow on: a list of directions without repeats |
| `max_instances` | no limit | stop after this many copies; a whole number, at least 1 |
| `materials` | true | wait until the construction networks reaching the next copy (summed; a player's personal roboport only where no roboport network reaches; on a space platform, its hub) can spare what it costs |
| `reserve` | 0 | how many of each item the network keeps back; a whole number, at least 0 |
| `max_building` | 2 | copies under construction at once; a whole number, at least 1 |
| `charted_only` | true | refuse chunks the force has not charted. With false, a real project also grows over chunks that do not exist yet, which it has the game generate (gate `chunks`); a dry run never does, and takes them for uncharted |
| `retire_depleted` | false | when true, a finished copy whose mining drills have nothing left to mine is retired; still so once the project has finished and been forgotten, but not once it is stopped. A socket whose next copy would stand on the copy it grows from, while that copy is retired so or due to be, waits for it to be removed (see `awaiting`) instead of closing as `overlaps-parent` |
| `dry_run` | false | plan the growth as outlines instead of stamping it; a plan never makes the game generate map |
| `order` | `"breadth"` | which open socket goes next: `"breadth"` the oldest, `"depth"` the newest (one arm grows out before the next starts), `"nearest"` the one nearest the seed (a compact blob) |
| `radius` | no limit | copies stay within this many tiles of the seed (every corner of a footprint), and a socket beyond closes as `outside-area`; a whole number, at least 1 |
| `enemy_distance` | 0 (off) | tiles to keep between a copy and an enemy spawner or turret, and a closer spot closes as `enemies`; a whole number, at least 0 |
| `landfill` | true | false refuses any spot with water (lava, oceans and space too) in its footprint, even where the design lays its own floor and even with `superforce`, and it closes as `water` |
| `open_early` | false | for fast fills: a copy's sockets open when it is placed, not when it is built. A copy with ore sensors still opens only once built and its ore is gone. Raise `max_building` with it, or the capacity gate still paces the fill. |
| `superforce` | false | buildings of the force in a copy's way are marked for removal and the copy is stamped anyway (a superforced paste) instead of the spot closing with `building`. That includes the copy it grows from: when that is the only copy in the way, the child is stamped over it, its parts in the way marked for removal, instead of the socket closing as `overlaps-parent`. The parent stays `complete` with what it keeps, and a part whose twin (same name, place and facing) already stands there is left as it is and counted as placed. A copy may also stand on water once the force has an enabled recipe for that floor's cover tile: landfill on water and Gleba's wetlands, foundation on lava and the oil ocean, ice platform on the ammoniacal ocean, platform foundation in space. The engine lays it where the floor keeps a part off (under its collision box, and where a tile rule wants ground, as an offshore pump's own tile) and under the design's paving where the paving can go on it (stone path cannot go on ice platform or platform foundation, so such a spot closes as `water`), and `materials` waits for it like any item. Without `superforce` such a spot closes as `water`, unless the design lays its own floor there. Trees and rocks are cleared either way. A dry run counts the same spots. |
| `preview_ghosts` | none | with `dry_run`: the plan's first this many copies (0 to 20) are also pasted as look-only ghosts of the neutral force: the parts that fit go down, and nothing in the way is cleared. No robots build them; they are removed when the plan is built (`build_project`), stopped or forgotten, and give way to any copy stamped or planned over them. A player's own blueprint paste does not move them: build or stop the plan first. |
| `mirrored` | false | grow the design's mirror image, as a paste flipped in hand does: a hidden twin of the design, made on first use and remade with each new version; refused with `"cannot-mirror"` for a design with rails, signals, train stops or wagons |

A dry run plans instead of stamping. Every spot that passes the checks becomes a planned copy, drawn as an outline, with no ghost and no need for materials or robots; the plan stops at 400 copies. Its `status.level` is `planning`, then `planned`, and `count` counts the planned copies. A finished dry run raises `on_project_finished` like any project. `build_project` starts a real project from a finished dry run's own params, with `dry_run` false, and stops the dry run. It returns nil and `"not-found"` for an unknown project, `"not-a-finished-plan"` for a project that is not a dry run or is still planning, or the real project's start refusal (for example `too-many-projects`).

A force keeps at most `seb-max-plans-per-force` plans: dry runs not stopped, planned ones waiting to be built included. Starting another stops its oldest ones first; each gets a `replaced` entry in its history, and `start_project` returns their ids as its second value. Plans never count toward `seb-max-projects-per-force`. A force also keeps only its newest 30 ended projects by id (stopped ones, and real ones that finished; `set_limits` key `ended_projects`, where 0 keeps them all): when another ends, older ones are forgotten with every mark they drew, and the functions that take a project id treat theirs as unknown (`get_project` returns nil, `stop_project` false). Their copies stay and go on as a stopped project's do, except that the copies of a finished project with `retire_depleted` still retire when their drills run dry.

`start_project` returns nil and `"invalid-design"` (the design cannot be stamped), `"off-grid"` (the seed's place is off the design's lattice), `"seed-occupied"` (the first copy would stand on copies already there) or `"too-many-projects"` (the `seb-max-projects-per-force` map setting; a dry run is never refused), besides the argument reasons above. Nothing else is checked at the call: a seed spot that is blocked closes as a socket on the first step of growth, and the project finishes with no copies and says why in `nothing_built`.

`get_project(...).state` is `growing`, `paused`, `finished` or `stopped`. `count` is the copies stamped so far, the `building` ones still under construction included. `open_sockets` does not include the `parked` ones (sockets waiting because no construction robots reach them) nor the `awaiting` ones: sockets whose next copy would stand on the copy they grow from while that copy is going for depletion (being retired for it, or due to be: `retire_depleted` is on, and its drills have nothing left to mine or its ore sensors see no ore left), with nothing else in the way. They wait for it to be removed and are tried again when its retirement ends. `gate` is what is holding growth back right now, or nil: `capacity` (`max_building` or the per-force setting), `chunks`, `missing-materials`, `robots-busy` or `busy` (the force has used up its share of server time, `seb-work-per-force`, or a pool's step stopped between its designs: the project waits its turn and closes nothing). `closed` counts every closed socket by reason: the stamp reasons above except the waits, and `enemies` (an enemy spawner or turret within `enemy_distance`), `overlaps-parent` (the copy would overlap the one it grows from, the project does not superforce, and that one is not going for depletion; one that is makes the socket wait, `awaiting`), `parent-retired` (that one was retired), `outside-area` (beyond `area` or `radius`), `count-reached` (`max_instances`, or the plan limit of a dry run) and `unknown-design` (a socket names a design or pool that does not exist). `blocked` is only how many blocked sockets the overlay still remembers (at most 50), so use `closed` for totals. `stalled` is how many copies make no progress now and `waiting_ore` how many finished copies wait for their ore; `status` and `history` follow. `nothing_built` is set only on a project that finished without stamping a copy: `{reason, position}`, the reason that closed the most of its sockets (`joined` included) and where it began.

`get_project(...).status` says why the project is where it is: `{level, reason?, item?, count?, unreachable?, ore?}` with `level` one of `growing`, `waiting`, `stalled`, `paused`, `finished`, `stopped`, and, for a dry run, `planning` and `planned`. A dry run waiting for its force's share is `planning` with `reason = "busy"`. Waiting reasons: `missing-materials` (with `item = {name, quality, count, have}`: what the next copy needs and what the network can spare), `chunks`, `robots-busy`, `busy`, `no-network` (`count` spots, every one left out of robot reach), `parent-retiring` (`count` sockets awaiting the removal of the copy they grow from, nothing else being built or tried), `ore-left` (`count` copies, every one left waiting for its ore). A stalled project gives the reason most of its `count` stalled copies give. A finished one gives its commonest closing reason other than joins (`reason`, `count`). Holding at the capacity gate is pacing and counts as `growing`, which also reports `unreachable` (spots out of robot reach) and `ore` (copies waiting for their ore).

`get_project(...).history` is the project's last ten notable events, oldest first: `{tick, kind, count, ...}` with `kind` one of `started` (`position`), `waiting` (`reason`, `item`, `item_count`), `blocked` (`reason`, `position`; once with `count-reached`, when the count closed every socket left), `unreachable` (`position`), `stalled` (`instance_id`, `reason`), `incomplete` (`instance_id`), `paused` and `resumed` (`player_index` when a player did it), `waiting-ore`, `ore-gone` and `depleted` (`instance_id`), `updated` (`copies`, `refused`), `finished` (`copies`), `built-plan` (on the project `build_project` started), and `replaced` (`limit`: a plan stopped to make room for a newer one). A wait for the force's share (`waiting`, `reason = "busy"`) is logged once, until the project runs out of sockets or another gate holds it. A repeat of the newest event (same kind, reason and item) takes its details and counts up (`count`).

## Events

`get_event_id(name)` returns the custom event's id for this session, or nil for a name not listed here. Resolve ids with it in both `on_init` and `on_load`, and never store them: they are generated again every session.

| Event | Payload |
|---|---|
| `on_instance_completed`, `on_instance_stalled`, `on_instance_retired` | `instance_id, design_id, version, force_index, surface_index, project_id, reason`. A stall's `reason` is `no-network` (no construction robots reach it), `missing-materials` (the network has nothing that could build one of its ghosts) or `no-progress`. A copy that `update_instance` moved raises `on_instance_completed` again when it is finished. |
| `on_instance_blocked` | `project_id, reason, position`: raised for each closed socket worth a mark on the map, which is every closing reason except `joined`, `outside-area`, `count-reached` and `parent-retired` |
| `on_project_finished` | `project_id, count` |
| `on_materials_missing` | `project_id, item, count`: raised when a project starts waiting for an item, or the item it waits for changes, not on every retry. `count` is how many the next copy needs in all. |

## Areas

| Function | Returns |
| --- | --- |
| `clear{force, surface, area, items?, cancel?}` | how many entities it ordered; or nil and `"invalid-params"`, `"unknown-force"`, `"unknown-surface"` or `"invalid-area"` |

`clear` orders deconstruction of everything of the force in the area, trees and rocks included; `items` (a list of item names) narrows it to what those items build, and `cancel = true` cancels those orders instead (returning 0). It does not wait for robots: the blueprint builder's Clear verb answers DONE once everything is gone.

## AI Agent Bridge tools

AI Agent Bridge scans every remote interface for a zero-argument `agent_tools_v1` and offers the tools it lists to its agent. Each takes one table, to which the bridge adds `force` (a force name), and returns plain data. The read tools are always listed; the write tools only while the map setting `seb-agent-write-tools` is on.

| Function | Returns |
|---|---|
| `agent_tools_v1()` | `{v = 1, tools}`: `tools` maps each tool below to `{desc, params?}`; `seb_project` declares `id` |
| `seb_projects({force})` | `{projects = rows}` for the force's projects that are not stopped, in id order. A row is `{id, design, state, status, built, building, spots_to_try}`: `design` is the design's name, `built` the copies not under construction, and `spots_to_try` counts open and parked sockets together. |
| `seb_project({force, id})` | what `get_project` returns, plus `design` (the design's name); or `{error = "no such project"}` for an unknown id or another force's project |
| `seb_designs({force})` | `{designs = rows}`. A row is `{id, name, version, ok, width, height, sockets, plug}`: `width` and `height` are in tiles (nil when the design cannot be stamped), `sockets` is the number of socket arrows and `plug` says whether it has an entry arrow. |

An unknown force gives empty lists (`seb_project` gives the error).

Write tools. Each acts only on the asking force's projects. A refusal is an error the agent reads (raised with `error(message, 0)`): "an admin has not turned on the Self-Expanding Blueprints write tools", "no such project" (unknown, stopped or another force's), or a bad `sides` word.

| Function | Returns |
|---|---|
| `seb_grow({force, design, x, y, count?, sides?, surface?})` | `{ok = true, project = id}`, or `{ok = false, reason}` with a `start_project` refusal reason. It starts a project as `start_project` does with `position = {x, y}`, `max_instances = count` and the default rules (charted chunks only, the materials gate on); `sides` is a comma-separated list of `north`, `east`, `south` and `west` (default east and south), and `surface` a surface name (default `nauvis`). |
| `seb_pause_project({force, id})` | `{ok}`: `pause_project`'s result |
| `seb_resume_project({force, id})` | `{ok}`: `resume_project`'s result |
| `seb_stop_project({force, id})` | `{ok = true}`; the project stops as `stop_project` stops it |

## Map settings

Runtime-global settings let a server admin limit what each force (a team under Multi-Team Support) may ask of the server. A force's work is charged to its own share of server time and the whole server's work is capped, so no force can slow the game for the others for long. One piece of work still runs in a single tick and can make that tick long, after which the force waits (DESIGN.md, "Sharing a server", says what is not bounded). A number of 0 is no limit.

| Setting | Default | Effect |
|---|---|---|
| `seb-max-projects-per-force` | 20 | The most projects a force may have growing or paused at once. `start_project` and `build_project` refuse another with `too-many-projects`. Plans have their own limit. |
| `seb-max-building-per-force` | 100 | The most copies under construction at once: the force's projects' copies and the ones its blueprint builders stamp, together, on top of each project's `max_building`. Growth holds at the capacity gate (`gate = "capacity"`) while the force is at the limit; a builder's Stamp waits. |
| `seb-max-plans-per-force` | 3 | The most plans (dry runs not stopped) a force keeps. Starting another stops the force's oldest plan first. |
| `seb-max-designs-per-force` | 100 | The most designs a force may register, never more than 30,000 (0 means 30,000). A new design past it is refused with `too-many-designs`; a new version of a registered design is always taken. |
| `seb-max-design-parts` | 5000 | The most parts a design may have: every entity, markers included, and every tile. A bigger one is refused with `design-too-big` when it is registered, as is one reaching more than 512 tiles across; designs already registered keep working. |
| `seb-max-builders-per-force` | 50 | The most blueprint builders of a force that take requests; the others show the limit error signal. |
| `seb-builders-charted-only` | on | Blueprint builders stamp, grow and search only on land their force has charted. Off: also on land the game has generated but the force has not charted. Builders never have the game generate map either way. A headless server charts only while a player is connected; what was charted stays charted. |
| `seb-work-per-force` | 500 | Microseconds of each tick a force's growth, plans, builders and new designs may use on average. Work is charged as it is done and may overdraw the account once; the force then waits (projects at the `busy` gate, builders read later) while the others go on. |
| `seb-work-per-tick` | 4000 | Microseconds of each tick the mod's work may use on the whole server, every force together; forces take it in turns, each within its own share. The work runs on every sixth tick, so that tick takes about six times this, plus the one piece of work that empties the account: a piece is charged after it ran and the server's account never carries a debt, so one force's big piece is its own debt and the others wait at most for the next run. One value for the whole server: `set_limits` has no key for it. |
| `seb-idle-robot-share` | 0 | The share of a network's construction robots, in percent (0 to 100), that must be idle before growth places the next copy there; below it the project waits with `robots-busy`, and a `stamp` with `materials` is refused with that reason. It applies wherever the materials check does (`materials` on, not a dry run), and not on a space platform. |
| `seb-agent-write-tools` | off | Lists the AI Agent Bridge write tools above. The bridge passes along a force the agent itself names, so a player can talk an agent into acting for another team: turn it on only where players trust each other. |

One force can be given its own values (an admin's trusted team, a scenario, a test):

| Function | Returns |
|---|---|
| `set_limits(force, limits)` | true, or nil and `"unknown-force"`, `"invalid-params"` or `"invalid-<key>"`. `limits` maps keys to values: `projects`, `building`, `plans`, `designs`, `design_parts`, `builders`, `work` (whole numbers from 0) and `builders_charted_only` (a boolean), and `ended_projects` (how many ended projects the force keeps: 30 unless set, no map setting; 0 keeps them all). Keys left out keep their current value. What waited on the old values looks again at once: projects held at the capacity gate, builders over the limit, and anything waiting for the old share of server time. |
| `get_limits(force)` | every limit as it applies to the force now, by the same keys; or nil and `"unknown-force"` |
| `clear_limits(force)` | true: the force follows the map settings again, and what waited on its old values looks again at once; or nil and `"unknown-force"` |

A force that is merged away or released by Multi-Team Support loses its own values with its other records, so a new team reusing the force starts from the map settings.

The functions that take an instance or project id (`get_instance`, `remove_instance`, `update_instance`, `get_project`, `pause_project`, `resume_project`, `stop_project`, `update_project`, `build_project`) do not check whose it is: they are for other mods and admins. Everything a player can reach (the window, blueprint builders, the AI Agent Bridge tools) checks the force.
