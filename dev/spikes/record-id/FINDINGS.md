# Spike: blueprint library record ids (Factorio 2.1.25 and 2.1.23)

Question: 2.1.25 gives a blueprint library record a `shelf_index` and a
`record_id`, and `on_gui_opened` and `on_gui_closed` carry the record. Can
state be kept per library record under that key? When does the id change,
where do the records live, and what does an older game give?

Measured 2026-11-18 with the probe mod in this folder: a graphical client on
2.1.25 (build 88022) driven by hand through the library window, the same
save loaded again, a new world on the same write-data, a headless server
with one client, and a client on 2.1.23 (build 87750). The shortened logs
are in `recorded-sessions.txt`. A script cannot put a record into the
library, so every record was put there with the mouse.

## What identifies a record

| Step in the library | shelf_index and record_id |
|---|---|
| Four items dropped into the player's library, one after the other | Shelf 1 (the player's index), ids 0, 1, 2, 3. The blueprint inside the book got id 4. |
| A record moved to another slot, two records changing places | Unchanged. The order of `player.blueprints` follows the slots, the ids do not. |
| The label edited in the record's window and saved | Unchanged. `on_gui_closed` carries the record with the new label. |
| A record moved into a book | Unchanged (shelf 1, id 2). The book's `contents` lists it. |
| A record taken out into the inventory | Gone from `player.blueprints` |
| The same blueprint put back | A new id (0 became 5) |
| A copy (`export_record`, `import_stack` into a new item, dropped in) | A new id (6) |
| A blueprint dropped on the game shelf | Shelf 65536, id 0: the game shelf counts on its own |
| The game-shelf record changed from script (`set_blueprint_entities`, `label`, `clear_blueprint`) | Unchanged, still valid. Game-shelf records are `valid_for_write`; the player's are not. |
| Save, quit, load the same save | Unchanged: the player's records 3, 1, 5, 6, the book's contents, the game record |
| A record added after the load | Id 7: the count goes on, ids are not handed out twice |
| A new world, same write-data | The same five player records with the same ids. The game shelf is empty. |

The player's shelf is kept in `blueprint-storage-2.dat` in the write-data
folder, for all of that user's saves. The game shelf is part of the save.
Two records with the same label and the same content differed only in
`record_id`.

So `shelf_index` and `record_id` name one library entry for as long as it
stays in the library: through moves, label edits, books, script edits and
save and load. Taking it out and putting it back, or copying it, makes a new
entry with a new id. A player's shelf belongs to the user, not to the save,
so the same key turns up in that user's other worlds. A mod that keys state
on the id keeps a fingerprint of the content beside it and checks it.

## The GUI events

| What is opened | on_gui_opened and on_gui_closed |
|---|---|
| The library window (B) | `gui_type=9` (`blueprint_library`), no `record`, `player.opened` nil |
| A record in the library (right click), also a book, also a blueprint inside a book | `gui_type=9` with `record`. `player.opened` is the LuaRecord. |
| That record's window closed (Escape or Save) | `gui_type=9` with `record`. `player.opened` is nil and `opened_gui_type` still reads 9, because the library is open behind it. |
| A blueprint item in the inventory (right click) | `gui_type=5` (`item`) with `item`, no `record` |

A record open is `gui_type == 9` with a `record`; the library itself is 9
without one.

Multiplayer, on the server: the record in `on_gui_opened` is a preview. Its
`type`, `label`, `shelf_index` and `record_id` read, but its content does
not (`BlueprintRecord cannot be read while it is a preview.`). In
`on_gui_closed` three seconds later the same record read normally.

## 2.1.23

`player.blueprints`, `game.blueprints` and `cursor_record` exist, and
`type`, `label`, `is_blueprint_setup` and `get_blueprint_entity_count` work.
`name`, `prototype`, `shelf_index` and `record_id` do not
(`LuaRecord doesn't contain key record_id.`). The GUI events for a record
have no `record` field and `player.opened` is nil. So read `event.record`
and `record.record_id` through `pcall` and use the id only when both are
there. 2.1.23 does not load a blueprint storage written by 2.1.25
(`Loading local blueprint storage failed: Map version 2.1.25-10 cannot be
loaded`) and starts with an empty library.

Not measured: a second player and a second shelf, whether a server script
can list a client's own shelf (the only list taken in multiplayer was on the
join tick, when a shelf still reads empty in single player too), deleting a
record.

## Rerun

```
dev/spikes/record-id/run.sh [blueprint-storage-2.dat]
```

Headless: lists both shelves at tick 30 in a private write-data and compares
the lines with `recorded-headless-2.1.25.txt` (an empty library): exit 0
when they match, 2 when they differ, 1 when the run did not finish. With a
blueprint storage file as argument, a copy goes into the private write-data
and its records are listed with their ids. On the join tick the shelf still
reads empty; by tick 30 it is loaded. Rerun after the move into this repo on
2.1.25: same lines, and with the storage file of the first run the same five
records and ids as in the new-world run.

The id rules need a client with this folder as a mod (`rec-probe`) and a
hand on the mouse. The steps, each followed by
`/c remote.call("rp", "dump", "<step>")` and a look at the `RP` lines in the
log:

1. `/c remote.call("rp", "give")` puts three blueprints and a book into the
   inventory. Open the library (B), left click an item in the character
   grid, left click an empty library slot. Repeat for all four.
2. Right click a record, close it. Edit a label and save.
3. Move a record to another slot. Move one into the book
   (`/c remote.call("rp", "book")` lists the book).
4. Take a record out to the inventory and put it back.
5. `/c remote.call("rp", "duplicate", 1, 3)` copies record 3 into an item.
   Drop it into the library.
6. Drop a blueprint on the Game blueprints tab, then
   `/c remote.call("rp", "edit_game_record")`.
7. Save, quit, load, and add one more record.

These steps were not rerun after the move. The helpers `give`, `duplicate`,
`book` and `dump` were run once headless against the storage file of the
first run; `edit_game_record` was not.
