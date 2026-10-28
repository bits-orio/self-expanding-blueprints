# S5 UPS: what a stamp costs

Question (DESIGN.md section 8): what do `build_blueprint` and recounts cost for a few hundred stamps of a large design? Should one stamp spread over several ticks?

Measured on 2.1.23 headless, 2026-10-26, with `helpers.create_profiler()` around four remote `stamp` calls per design (pre-check of every part with `can_place_entity`, the forced `build_blueprint`, tagging and registering every ghost). Designs were square grids of solar panels.

| Design | Four stamps | Per stamp | Per entity |
|---|---|---|---|
| 16 entities | 0.82 ms | 0.20 ms | 13 µs |
| 64 entities | 3.72 ms | 0.93 ms | 15 µs |
| 256 entities | 10.37 ms | 2.59 ms | 10 µs |

So a stamp costs about 10 to 15 microseconds per entity. A 1000-entity design would take about 10 ms, more than half of a 16.7 ms tick.

Decision: one stamp is not split across ticks (all-or-nothing is simpler kept in one tick), but the growth loop's work budget charges a stamp by its size (`loop.lua`: at least four units, one unit per 32 entities, sixteen units per tick per project). A design of a few hundred entities therefore stamps at most one copy per tick, and the default `max_building` of two keeps the in-flight count small anyway. Recounts were measured at about 0.05 ms per 100 ghosts earlier (ADR-0004) and stay unbudgeted.
