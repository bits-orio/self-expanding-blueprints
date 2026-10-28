# Spike S8: charting on a headless game (Factorio 2.1.23)

Question: can tests (and a dedicated server with nobody online) rely on
`LuaForce.chart` and `is_chunk_charted`?

Runs: this spike under `dev/run-spike.sh s8-chart 2001` (benchmark), the same
save under `--start-server` with no client, and a server with a graphical
client joining after 10 seconds (scratch copy of `dev/run-mp.sh`).

- Benchmark and server with nobody connected: nothing is ever charted. Not
  the spawn area, not a powered radar's own chunk, not `force.chart` called
  in `on_init` or in a tick, not `chart_all`. `is_chunk_visible` stays false.
- Server, client joins at about tick 1400: the chunks charted by script
  earlier (while nobody was on) and the spawn area are charted at the next
  check. After the client leaves, they stay charted.

So charting is queued while no player is connected and done once one is;
charted state is part of the save and survives everyone leaving. A rule
"charted land only" therefore works on a real server, also for a team's
builders running while the team is offline. Headless tests can never see
charted land: the test mod turns `seb-builders-charted-only` off, and
`cases/limits_builders.lua` checks the rule through a per-force override instead.
