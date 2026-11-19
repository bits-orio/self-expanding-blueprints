# Spike: LuaEntity.get_signals_changed (Factorio 2.1.25)

Question: `entity.get_signals_changed(wire_connector_id, tick_of_last_check)`
says whether the signals on a circuit connector changed. When exactly is it
true, what does the tick argument do, does one caller's question change
another's answer, when is it nil, and what does it cost next to
`get_signals`?

Measured on 2.1.25 (build 88022), headless in the game's test mode, with the
probe mod in this folder. First run 2026-11-18 with Space Age on and three
mods asking in the same tick. Rerun 2026-11-19 from this folder with the
base game: the probe alone and with the two other mods. The lines of the
three-mod run are in `recorded-2.1.25.txt`.

| Step | Result |
|---|---|
| A constant combinator's value is written at tick N | false at N (also when asked twice), true at N+1 only, false at N+2. The same on the combinator, the lamp and the arithmetic combinator's input. |
| The signal type changes, the count stays | The same: true at N+1 only |
| Items go into a wired chest at tick 50 | Chest and pole true at 51 only |
| The output of a powered arithmetic combinator | One tick later: true at N+2, on the output connector and on the lamp wired to it |
| Right after wiring (tick 3) | true at ticks 3 and 4 on every connector of a wired entity, false from tick 5 (the combinator's output one tick longer) |
| A wire is removed at tick 140 | true at 140 for a caller that runs after the removal, and at 141; false at 142. A mod whose handler ran before the removal saw false at 140. The lamp's green connector reads true as well. |
| The wire is put back at 150 | true at 150 and 151 |
| Asked twice in one tick, or by three mods in one tick | Everyone gets the same answer. Asking uses nothing up. |
| Tick argument: the value changes at 70 and back at 75, asked at 120 | Without an argument false. With 60, 70, 74 or 75 true. With 76 false. It is true when something was written after that tick, also when the value is back where it was. |
| Tick argument 0, 99999, -5 | true, false, and an error: `Given MapTick value -5 is outside of valid range. Allowed values are from 0 to 4503599627370496, or inf.` |
| A red change, asked on green | false. Each connector answers for itself. |
| Connector ids | `circuit_red` and `combinator_input_red` are both 1: a lamp asked with `combinator_input_red` answers as for `circuit_red`. `pole_copper` on a lamp or a pole gives nil. |
| An entity that never had a wire (lamp, furnace, belt) | nil, no error. After `get_wire_connector(id, true)` it reads false. |
| An entity whose wire was removed | false, not nil |
| The probe's own lines, alone and with two other mods asking every tick | The same (rerun) |

Cost of 2000 calls on one lamp:

| Call | Space Age, 300 signals | Base game, 253 signals (rerun) |
|---|---|---|
| `get_signals` | 202 to 208 ms | 197 to 229 ms |
| `get_signals_changed`, with or without the tick | 0.22 to 0.58 ms | 0.20 to 0.31 ms |
| `get_signal` for one signal | 0.62 to 0.77 ms | 1.0 to 1.5 ms |

On the tick a combinator with hundreds of signals is connected,
`get_signals` on the lamp still returns nothing. After a filter edit at tick
175 the call says false at 175, true at 176 and false at 177.

So the call answers "was anything written on this connector since tick T"
for a fraction of a microsecond, about a thousand times less than reading
the signals. It is still a question a script has to ask: nothing is raised.
A caller keeps the tick of its own last check and passes it, asks each
colour it reads, takes nil as "no wire here", and reads once without asking
after it has built or rewired something itself.

Also seen, fields that came with 2.1.25: a chest's control behavior has
`read_empty_slots` (false by default, writable) and `empty_slots_signal`
(signal-E). A rocket silo's has `read_launched` (false) and `launched_signal`
(signal-R). A selector combinator's parameters take `index_comparator` and
`index_constant` and read them back.

Not measured: an engine before 2.1.25, circuit networks merging or
splitting, a gap of millions of ticks, whether the empty slots signal shows
up on the wire.

## Rerun

```
dev/spikes/signals-changed/run.sh [space-age]
```

Headless, a few seconds. Runs the probe alone and with the two other mods,
prints the `SC` lines, and compares the three-mod run with
`recorded-2.1.25.txt` (timings and item counts aside): exit 0 when the lines
match, 2 when they differ (the engine behaves differently), 1 when a run did
not finish. Rerun after the move into this repo on 2.1.25, base game and
Space Age: same lines.
