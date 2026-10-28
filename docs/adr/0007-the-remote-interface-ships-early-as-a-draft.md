# The remote interface ships in v0.1, as a draft

DESIGN.md puts the remote interface in a later milestone. It ships now, marked as a draft, because the headless tests need it: a test mod runs in its own Lua state with its own `storage`, so requiring the mod's modules from a test mod exercises copies that never see the real game state. The tests drive the mod only through `remote.call("self-expanding-blueprints", ...)` and the custom events.

The functions implemented are the v0.1 subset of DESIGN.md section 6: `register_design`, `list_designs`, `stamp`, `remove_instance`, `get_instance`, `start_project`, `get_project`, `pause_project`, `resume_project`, `stop_project` and `get_event_id`. Names and shapes may change before v1, when the interface becomes stable.

Supporting choices:

- **Arguments are checked at the boundary.** A bad value returns `nil, "invalid-<field>"` before anything is stored, instead of failing later inside a scheduled handler, where the error names no caller. Positions are accepted as `{x, y}` too, areas in all three engine forms, and coordinates only within the map's +-1,000,000 tiles. A force or surface of the wrong kind, or an index the engine refuses, is just unknown.
- **`stamp` and `start_project` read a place the same way.** `position` lands the entry arrow on that tile, or the vanilla anchor without one; `build_position` is the raw build position (ADR-0006).
- **Their defaults differ on purpose.** A remote `stamp` is a single stamp another mod asked for, so it skips the charted-land and materials checks unless asked (`charted_only` and `materials` default to false). `start_project` grows like the player's grow tool, so both default to true.

The full parameter list is in [docs/remote-interface.md](../remote-interface.md).
