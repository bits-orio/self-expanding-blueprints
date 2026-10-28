# S6: what registering a design costs

Question (from the second review): Capture runs synchronously in one tick. What does registering a design cost, and what limit keeps a circuit-driven Capture from freezing a multiplayer game?

Measured on 2.1.23 headless, 2026-10-26, with `helpers.create_profiler()` around the remote `register_design` and around Capture's own steps (`create_blueprint` with tiles, `export_stack`, then registering the string). The spike's `control.lua` is kept beside this file; run it with the mod linked next to it.

| What | Cost |
|---|---|
| First design in a save (both lab surfaces made, their chunks generated) | 35 ms |
| A small design (1 to 16 solar panels: calibration and gallery picture) | 0.5 to 1.5 ms |
| A design that opens new gallery chunks | 7 to 9 ms |
| Capture of a concrete floor, 32 x 32 (create, export, register) | 60 ms |
| 64 x 64 | 180 ms |
| 128 x 128 | 640 ms |

Tiles dominate: each floor tile is exported, imported, stamped four times for calibration and once for the picture, about 35 microseconds a tile in all. Entities cost far less.

Decision: Capture is held to 64 x 64 tiles (it was 512 x 512, about 10 seconds). Registering through the window is a one-off player action and keeps no limit.
