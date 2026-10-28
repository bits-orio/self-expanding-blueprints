# Playtest checklist

What the headless suite cannot reach, because no player exists headless. `dev/run-gui.sh` starts a client on a lab world with a roboport network, stock and a solar-cell blueprint in the cursor; `dev/gui-drive.sh` clicks, types, runs Lua (`lua`, which confirms the session's first command for you) and takes screenshots: `snap` renders a map region with the game's own screenshot (no cursor or character), `shot` captures the window when those matter. The client runs on a private X display, so it never touches your mouse, focus or clipboard: `dev/gui-drive.sh watch` prints a localhost link that shows it in a browser tab (`watch play` lets you click and type in it too), and `FACTORIO_DISPLAY=desktop dev/run-gui.sh` opens it on your own screen instead. Do one pass with base only and one with Space Age.

Each line is an action, then the expected result.

## Window

- [x] Shortcut bar button and SHIFT + ALT + G open and close the window; the cursor keeps what it held. (ALT + G is vanilla "give green wire"; see ADR-0008.)
- [x] Holding a labelled blueprint, the add button reads **Add “Solar cell” as a design**; pressing it prints "Registered Solar cell (version 1)." and the button turns into **Update “Solar cell” (it becomes a new version)**. (0.2)
- [x] With an empty cursor the add button is greyed out and its tooltip says to pick up a blueprint first. (0.2)
- [ ] Picking a blueprint from the blueprint library (B) updates the add button's caption too (if not, on_player_cursor_stack_changed does not fire for library records).
- [ ] The question mark opens "How growing works" in its own window beside the main one: tabs for sockets and plugs, ore sensor, probe and port, each with a picture. It drags by its title bar, stays open when the main window closes, and reopens where it was left, on the same tab. (0.2)
- [x] Hovering a design shows a card beside the window with its picture (ghosts on the gallery surface), size and parts; moving away hides it. (0.2)
- [x] The Grow section shows the chosen design's picture. (0.2)
- [ ] Hold a labelled book of about 20 blueprints of about 1,000 parts and press Add: every blueprint in it becomes a design, one after another ("Registered X (version 1)" lines in chat, the list grows), the first design is selected, and the pool line comes after the last. The book can be moved or put away at once. Add on a second book meanwhile says "Waiting for your team's share of server time". (0.2)
- [ ] Holding a blueprint from the blueprint library (not the inventory): it registers the same way.
- [ ] Hold a blueprint with more parts than seb-max-design-parts (markers included), or one reaching more than 512 tiles across, and press Add: "It is too big: at most 5000 parts and 512 tiles across."; nothing is registered. With 100 designs, a new name says "Your team already has as many designs as the server allows (100)."; a new version of an existing design is still taken. (0.2)
- [ ] Press Add twice in a row on a 5,000-part blueprint: the second press says "Waiting for your team's share of server time" until the first one's cost is paid off. (0.2)
- [ ] Hold a book with more than 1,000 blueprints and books (the books inside counted): the add button is greyed out and reads "This book is too big to add: it holds more than 1000 blueprints and books". A book that fits but whose blueprints add up to more than 250,000 parts: Add says "This book is too big: its blueprints may have at most 250000 parts in all, floor tiles included."; nothing is copied. (0.2)
- [ ] Refresh button on a row with a blueprint in hand: the design's version goes up; existing copies keep theirs.
- [ ] Trash button: the design goes; copies already built stay.
- [x] Direction checkboxes, "Stop after" and "Wait for materials" keep their values when the window reopens.
- [x] The projects list shows one row per project: locate, a status light, the design icon, "#1 Solar cell Growing" with counts, and why it waits when it does; buttons inside the window, no horizontal scrollbar. (0.2)
- [x] Hovering a project's text shows its recent history with times ("5 s ago: Blocked by water at 30, 12 (×3)"), fresh on every hover. (0.2)
- [x] Stopping a project takes every mark it drew off the map (19 render objects before, 0 after). (0.2)
- [x] A finished project keeps a disabled pause button, so its stop button never moves under the cursor.
- [x] Locate (the reticle) on a growing project: remote view goes to the copies under construction with a blinking outline; right-click shows the whole field.
- [ ] Locate from the map editor: a map tag with the project's place is printed instead.

## Grow and Fill an area

- [x] **Grow**: the window closes and the design is in hand, labelled with its name, inside a dashed frame that turns red where something is in the way. (2026-10-27, GUI client)
- [x] Click with the design in hand: one project starts, its first copy exactly where the ghosts were; the hand is empty after. (2026-10-27)
- [x] Multiplayer join (dev/run-mp.sh) after the window and flip work: MP JOIN OK, no desync. (2026-10-27)
- [x] Flip the design in hand and click: the copies are its mirror image and grow toward the mirrored directions (east becomes west); the project shows under the design as "flipped · paste axis". (2026-10-27, flip through the build call; the keys untested)
- [ ] Turn the design with R and click: the copies turn and grow toward the turned directions; with "Keep the directions to the world", they grow toward the ticked sides of the world.
- [ ] Flip a design with a rail: "can't be flipped", nothing starts.
- [x] Plan only shows "Plan at most 5"; a plan stops at 5 copies. (2026-10-27)
- [x] The window opens on the designs; a design's row says how many projects it has; clicking it opens its page with only its projects; Designs goes back. (2026-10-27)
- [x] Hover a project's row: its copies are outlined in yellow on the map until the pointer leaves. (2026-10-27)
- [ ] Locate (show on map) a project: the view moves there and its copies stay outlined for ten seconds.
- [x] Keep clear: the button gives the Keep clear tool; a click marks one tile, a drag marks the rectangle, tiles under buildings are skipped. (2026-10-27)
- [ ] Keep clear and Ore sensor: right-click takes one marker off, right-drag all in the rectangle; a drag over more than 64 x 64 tiles is refused with a line at the cursor.
- [ ] Ore sensor: the button (now "Ore sensor") gives the Ore sensor tool; a drag over drills puts a sensor on every tile, drills included.
- [x] Click on the map: a copy is stamped centred on the click and robots build it; its outline reads "Building: N left" until done.
- [x] With "Stop after 12": growth stops at 12; the project row reads "Finished 12 built ... Count reached".
- [x] Fill an area, then drag a rectangle from its bottom-right corner to its top-left: the first copy goes in the bottom-right corner and copies spread west and north, stopping at the edges. (2026-10-27)
- [x] Show on map from the window in the character's view: the view moves to the map and the window stays open. (2026-10-27)
- [x] Rename a design from its page (type, Enter): the page, the list and its projects' rows show the new name; chat says "Renamed A to B". (2026-10-27)
- [ ] After a rename, a design whose socket names the old name still attaches the renamed design; a new blueprint with the old name makes a new design.
- [ ] More options folded with Plan only on: the row reads "More options (on: plan only)" and the count reads "Plan at most".
- [x] Grow toward water: the socket at the shore shows a red cross with "Blocked by water".
- [ ] Click with the design in hand where no construction robots reach: the first copy's ghosts go down anyway; the next copies wait for robots. (Headless: cases/feedback.lua.)
- [ ] While a copy is under construction, a faint arrow and a dashed outline show where the next copy goes. (Headless: cases/feedback.lua.)
- [x] Remote view: the window opens, Grow puts the design in hand and a click on charted land starts the project (uncharted land shows it red, as any blueprint). (2026-10-27)
- [x] Right-drag with the area tool over a copy: exactly its entities are removed by robots; the neighbours stay.
- [ ] With three plans, start a fourth: a line says "Plan #N stopped: your team keeps at most 3 plans at a time, so a new one replaces the oldest."; the oldest plan's row history reads "Stopped for a newer plan: your team keeps at most 3 plans". (0.2)

## Mining (0.2)

- [ ] Draw a mining design with a drill and an ore sensor on it, plus a socket: a finished copy shows its watched area in amber with "Grows on when the ore in the marked area runs out"; when the drill has mined it out, the next copy comes. (Headless: cases/mining.lua, with depleted resources.)
- [ ] A sensor with the signal R = 1 watches a 3 × 3 square around it: growth goes on before the drill's whole 5 × 5 area is mined out.
- [ ] Grow with "Remove copies whose ore runs out": a copy whose drills have nothing left to mine is removed by robots about ten seconds later.
- [ ] A creeping miner from two designs: a head (a drill facing west with a sensor, a plug on its west edge, a socket past its east edge naming the head and one on the drill naming the belt piece) and a belt piece (belts and a pole, with a plug). Grow the head along an ore strip with "Remove copies whose ore runs out": once a head's ore is gone the next head goes on, the belt socket shows "Waiting for the copy it grows from to be removed", and when robots have removed the head a belt piece is built where it stood, carrying the next head's ore home. Without the option the belt socket shows "Would overlap the copy it grows from". (0.2.2; headless: cases/creeper.lua.)

## Probes, pools, plans and updates (0.2)

- [ ] Draw a probe with the iron ore signal into a design and grow it over the edge of an ore patch: copies stop where the ore ends, with "Not the right ground".
- [ ] Add a labelled book of two designs, name the book in a socket: the first design that fits is built there.
- [x] Tick "Plan only" and grow: outlines, no ghosts, the row says "Planning", then "Plan" with a green check; the check grows it for real. (Seen in a client.)
- [ ] "Plan only" with "show the first 3 as ghosts": the first three copies appear as ghosts that robots leave alone; growing the plan (or stopping it) removes them. (Headless: cases/plan.lua.)
- [ ] "Replace buildings in the way": a copy over one of your chests is built and the chest is marked for removal; without it the spot is skipped. (Headless: cases/plan.lua.)
- [ ] Update a design with a changed blueprint: its project's row offers the update button; shared parts stay, new parts come as ghosts, dropped parts are removed.
- [ ] Choose a research on a design row, then finish that research: copies update.
- [x] The list button on a project row opens its copies that need a look; remove works; locate goes to the copy. (Seen in a client.)

## Circuits (0.2)

- [x] Opening a blueprint builder shows its own window with every signal, named, instead of the decider's. (Seen in a client.)
- [ ] Wire a constant combinator with Stamp = 1, Design = <number>, X, Y to a builder: Request accepted 1, then Request done 1 with the copy's number once robots built it. (Headless: cases/circuit.lua covers all ten verbs.)
- [ ] Grow from a builder with Pause on a lever: growth pauses while the signal is there.
- [ ] Stamp out of robot reach from a builder, then put Stop on its input: Request failed with "Error: stopped", and the next request is accepted. (Headless: cases/circuit2.lua.)
- [ ] Place a 51st blueprint builder (default limit 50): its window says "Your team already has 50 blueprint builders at work, the most this map allows. This one takes no requests until one of them goes.", its output shows "Error: a server limit for your team", and it takes requests once a working builder is removed. (0.2)
- [ ] With AI Agent Bridge and the map setting "Let AI agents change growth" on, ask the agent in chat to pause a project: its row reads Paused. With the setting off, the agent says it cannot.

## Tips, scenario, platforms (0.2)

- [x] Tips and tricks has a "Self-Expanding Blueprints" section; all six entries play simulations that run the mod. (Seen in a client.)
- [ ] The "Seed only" scenario starts without a character, with a robot network and the "Seed solar" design ready. (Loads headless without errors.)
- [ ] On a space platform, grow a design with foundation tiles from the hub's inventory. (Headless under Space Age: cases/platform.lua.)

## Blueprint Primer

- [ ] With Blueprint Primer installed, prime a furnace and a chest, blueprint them, register the blueprint and grow it: every copy's ghosts carry the exact requests, robots deliver them, and a copy shows complete only once they are in. (Headless, cases/priming.lua checks the same insert plans without loading Primer itself.)

## Markers

- [ ] Draw a build with a column of Keep clear past its edge and grow it: the column stays an empty lane between copies; a tree on it is cut down; a chest on it stops that copy (with "Replace buildings in the way" it is removed). (Headless: cases/clear.lua.)
- [ ] With Negative Space installed, blueprint a build with its markers and grow it: copies finish, its plain markers keep their tiles clear.
- [ ] Draw a drill at the edge of a patch, half on ore, with its ore sensor on a drill tile that has no ore under it: the copy still waits for the drill's whole area to run dry (a sensor on a drill watches the drill's area, whatever is under its own tile).

- [x] Socket, Plug and Sensor buttons put 20 markers in the cursor; placed markers show their arrow, turned with R. (Refill when the stack runs out: not yet seen.)
- [ ] A socket's description names a design: growth through it stamps that design.
- [x] Pasting a design with markers by hand (ordinary blueprint placement) leaves no marker ghosts behind (a marker ghost would raise a lasting "no material for construction" alert).
- [x] Copying in-flight stamp ghosts with Ctrl+C gives a blueprint without instance tags.
- [ ] A marker placed as a ghost in remote view stays (it is part of a design being drawn).

## Multiplayer

- [x] Host a game, start a project, let a second client join mid-growth: no "mod event handlers are not identical" refusal. Automated by `dev/run-mp.sh`: a headless server grows a project, a real client joins over localhost, and the run fails on a refusal, a desync or a script error.
- [ ] Two players on different forces each see only their own designs, projects and overlay.
