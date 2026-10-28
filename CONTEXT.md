# Self-Expanding Blueprints

Grows a factory from the player's own blueprints. A player registers a blueprint as a design, draws arrows into it where the next piece attaches, and the mod runs the growth loop: pick the next spot, check it, stamp it, wait for the robots, open the next spots. Every stamp is remembered, reports when its robots are done, and can be removed exactly. Exposes the `self-expanding-blueprints` remote interface (a draft until v1).

> This glossary is seeded from `DESIGN.md` and the code. Keep it and the code in the same vocabulary. Where players see another word than the code uses, both are given.

## Language

**Design**:
A blueprint registered under a name and a number, with a version. Numbers are unique across forces, so one can never name another team's design. Registering a blueprint whose name is taken creates the design's next version, but only if that version can be stamped: a failed update leaves the design as it was (ADR-0009).
_Avoid_: template, plan, pattern

**Library**:
A force's designs, held as blueprint stacks in a script inventory (`storage.libraries[force_index]`). Each MTS team has its own.

**Stamping copy**:
The blueprint the mod actually builds: the player's blueprint with snapping cleared and one anchor added. Derived from the registered blueprint at every registration (ADR-0002).

**Anchor**:
The internal 1x1 entity added inside a stamping copy's bounds so calibration can always find one ghost. Players never see it; its ghost is destroyed the tick it is made.

**Calibration**:
Stamping a design's copy at the origin of the hidden lab surface `seb-calibration` in each direction to measure `offsets[d]`, where its blueprint origin lands relative to the build position.

**Offsets**:
Per build direction, the measured translation in `world = P + offsets[d] + rotate(bp, d)`. Everything about placement follows from them.

**Lattice**:
The step a design's build positions must keep: 1 tile, or 2 for designs whose entities snap to the rail grid (`build_grid_size` 2).

**Footprint**:
The whole tiles a stamp covers: the union of its entities' tile footprints (tile size, turned for east and west) and its tiles. Markers are not part of it.

**Marker**:
A socket arrow, plug (entry) arrow or ore sensor drawn into a design. A constant combinator underneath, with an empty collision mask (ADR-0001), so its description and signals travel with every blueprint.
_Avoid_: flag, beacon, sign

**Socket**:
A marker pointing where the next design attaches, facing that way. Its description names the design to attach; empty means the same design.

**Implicit socket**:
A socket on a plain design's footprint edge, one per direction chosen in the window (Level 1). It attaches the same design one repeat further on. Whether a copy opens implicit or drawn sockets follows the version it was stamped from, and only copies of the project's own design open implicit ones: a plain design reached through a drawn socket is an end piece.

**Entry** (players see **Plug**):
The marker that says where a design attaches. A child is turned so its entry faces the socket's direction and placed so the entry lands on the socket: the plug goes into the socket. At most one per design. A design without one attaches by the middle of its back edge, unturned (D18). The prototype keeps the name `seb-entry`, so drawn blueprints keep working (D24).

**Ore sensor**:
A marker (`seb-sensor`) that makes a design's finished copies open their sockets only once no ore is left in the area it watches: the mining area of the drill it sits on, or the square of 2R + 1 tiles around it when its signal R is set, or else its own tile. A copy waiting for that is shown with its watched areas (D28).

**Probe**:
A marker (`seb-probe`) stating what must be true on its tile before a copy is built there: some resource, the resources its signals name, water, or with the signal "deny" the opposite (ADR-0016).

**Pool**:
A labelled blueprint book, added to the library: its designs in order under the book's label. A socket whose description names the pool stamps the first of its designs that fits (ADR-0016).
_Avoid_: variant set, group

**Port**:
A marker (`seb-port`) placed on a combinator of a design: that combinator is each copy's circuit mailbox, read and written by a blueprint builder by the copy's number.

**Retire on depletion**:
A project option (`retire_depleted`): a finished copy whose mining drills have nothing left to mine retires after its output has had time to drain. A socket whose child would stand on such a copy waits for it to go (see Awaiting socket).

**Repeat**:
How far an implicit socket steps: the blueprint's snap grid when it has one, else its footprint, rounded up to the lattice. Recorded on each instance, so a design updated mid-project still abuts its older copies. A blueprint with absolute snapping also keeps its world grid: seeds land in a grid cell, as a hand paste would.

**Seed**:
A project's first stamp, placed by one of four places: `position` (the entry arrow lands on that tile; the vanilla anchor without one), `build_position` (the raw build position), `point` (the footprint centred there, a click) or `area` (filled from its top-left corner, a drag).

**Stamp**:
One `build_blueprint` of a design's stamping copy, all or nothing (ADR-0003). As a noun in player-facing text, the copy it made.
_Avoid_: paste, deploy, place (for the whole operation)

**Instance**:
The record of one stamp: its design and version, force, surface, build position and direction, footprint, the entities it built and the tiles it laid, its state. `storage.instances[id]`. A retired instance is forgotten once its `on_instance_retired` is out, unless it was retired for depletion and its project still grows or is paused: that one stays on record until the project ends, because growth parents from it (D45).
_Avoid_: copy, child (except for the parent and child relation itself)

**Instance states**:
`building` (ghosts left), `complete`, `incomplete` (a ghost vanished unbuilt), `stalled` (no progress for a while, with why: no network, missing materials or no progress), `retiring`, `retired` (ADR-0010). A `retired` instance is rarely seen: its record is forgotten right after the event (see Instance).

**Project**:
One growth run: a seed design, a surface, a place, rules and gates. `storage.projects[id]`. A team keeps its newest 30 ended projects (stopped, or finished); older ones are forgotten.
_Avoid_: job, task, run (in code)

**Frontier**:
A project's open sockets, first in first out (breadth-first growth).

**Gate**:
What holds the head of the frontier without closing a socket: capacity (too many instances building), materials (the construction network lacks something), robots-busy (fewer of the network's construction robots are idle than `seb-idle-robot-share` asks), chunks (still generating), busy (the team's share of server time is used up for now, or a pool's step stopped between its designs: it waits its turn). A gate shows on the frontier's first socket (ADR-0011).

**Share of server time**:
The estimated microseconds per tick a team's work may use on average (`seb-work-per-force`, `budget.lua`, D44). Growth steps, plan steps, builder reads and requests, updates in place and registered designs are charged to the team's account as they are done; one piece of work may overdraw it, and the team then waits (a project at the `busy` gate, a builder read later) while other teams carry on. All teams together draw on a server-wide account (`seb-work-per-tick`, D46), which the teams take in turns and which never carries a debt. Players read it as "Waiting for your team's share of server time".
_Avoid_: budget, quota (in player-facing text)

**Limit**:
A value the map settings give each team, which a remote caller can override for one force (`set_limits`): how many projects, plans, designs, parts per design, blueprint builders and copies in flight it may have, its share of server time, and whether builders keep to charted land. For a number, 0 means no limit. Players read a refusal as "your team already has as many ... as the server allows"; a builder answers with the `limit` error signal (D45).

**Project status**:
Why a project is where it is, derived from the registry on demand (`status.lua`): growing, waiting (a materials, map or share-of-server-time gate, every spot left out of robot reach, spots awaiting the removal of the copy they grow from, or every copy left waiting for its ore), stalled (a copy makes no progress), paused, finished. Holding at the capacity gate is pacing, not waiting (D26).

**History**:
A project's last ten notable events as data: started, waiting, blocked, unreachable, stalled, incomplete, paused, resumed, waiting for ore, ore gone, depleted, updated, built from a plan, replaced (a plan stopped for a newer one), finished. A repeat of the newest entry counts up instead of adding a line. Shown in the projects list's tooltip and returned by `get_project` (D26).

**Parked socket**:
A socket no construction robots reach. It waits on its own, so it never holds the rest of the frontier, and returns to the frontier every ten seconds to be tried again. A project with parked sockets keeps growing.

**Awaiting socket**:
A socket whose child would stand on the instance it grows from while that instance is going for depletion (being removed for it, or due to be: its project retires depleted copies, and its drills have run dry or its sensors see no ore left). It waits on its own, out of the frontier (`project.awaiting`), and returns when that instance's retirement ends, so the child goes down where its parent stood: the belt piece behind a creeping miner (D53). Players read it as "Waiting for the copy it grows from to be removed".

**Closed socket**:
A socket that will never stamp, with a reason: joined, water, cliff, building, no resource, uncharted, off-grid, misaligned, stamp short, overlaps its parent, parent retired, outside the area, count reached, unknown design, invalid design. Joins, area edges, counts and retired parents are the normal shape of growth and are only counted; the rest are marked on the map. Once its count is reached a project closes every socket left at once, and its history says so once.

**Joined**:
A socket whose child would overlap another instance. The normal way a fill closes.

**Recount**:
Searching an instance's footprint for what is still to be built: its tagged ghosts, its tile ghosts, item requests on its entities. Runs once events go quiet; counts are recomputed, never decremented (ADR-0004).

**Retire**:
Remove exactly what an instance built: destroy its unbuilt ghosts, order its entities and tiles deconstructed, and mark it retired when they are gone; its record is then forgotten (see Instance).
_Avoid_: delete, demolish (for instances)

**Overlay**:
Render objects derived from the registry: building, stalled, incomplete and retiring instances as outlines with a label, copies waiting for their ore as their watched areas, the next open sockets as arrows (at most 100 a project), blocked sockets as crosses with their reason. Complete instances draw nothing, and nothing of a stopped project is drawn (D25).

**Plan** (dry run):
A project that plans instead of stamping: every spot that passes the checks becomes a planned copy (footprint and sockets, no entities) and opens its sockets at once, so the plan shows as outlines. Built, it becomes a real project with the same start (ADR-0016). A team keeps a few at a time (seb-max-plans-per-force); a new one stops the oldest.

**Update in place**:
Moving a copy to its design's newest version without tearing it down: the new version is built superforced over it, laid where most parts coincide; shared parts stay, new parts come as ghosts, dropped parts are deconstructed (ADR-0017). A design can name a research that updates its copies when finished. Many copies at once wait in their team's line of updates and are made a few at a time.

**Order**:
Which open socket a project tries next: breadth-first (the oldest, the default), depth-first (the newest) or nearest-first (nearest the seed).

**Blueprint builder**:
`seb-builder`, the circuit layer's combinator. A **request** is a **verb** signal (Stamp, Grow, Remove, Clear, Sense, Find, Capture, Upgrade, Read, Write) whose value is a request number, held on its input with its inputs; the builder answers ACK with the number, then DONE, or ERR with one named error signal. One request at a time (ADR-0015). A team has at most `seb-max-builders-per-force` working builders; the others wait and show the `limit` error.
_Avoid_: deployer, chest (Recursive Blueprints' words)

**Gallery**:
The hidden lab surface `seb-gallery` holding one copy of every design as ghosts of its force, so the window can show a picture of it through a camera: in a card beside the window while a design is hovered, and in the Grow section for the chosen one (D27).

**Grow tool**:
the chosen design in hand (`seb-grow-blueprint`, inside a dashed frame of `seb-grow-frame` pieces), put there by the window's Grow button: its ghosts follow the pointer and a click grows the first copy exactly there; the paste itself is called off. The area tool (`seb-grow-tool`, the selection tool beside Grow): click grows from there, drag fills the rectangle, right-drag retires the instances the drag touches.
