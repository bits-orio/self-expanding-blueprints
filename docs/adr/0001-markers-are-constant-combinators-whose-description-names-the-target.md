# Markers are constant combinators, and a socket names its target in its description

Socket and entry arrows are copies of the constant combinator with an empty collision mask. A socket's target is the text of its description: empty means "the same design again", anything else is the name of a design in the force's library. Settings therefore live in the entity itself, and every blueprint, book, library edit and copy-paste carries them natively.

Spike S2 decided this (`dev/spikes/s2-markers/FINDINGS.md`). A combinator's description and signals are captured by `create_blueprint` from real markers and from ghosts alike, survive export, import and books, and can be read back from a stamped ghost. The alternative, a `simple-entity-with-owner` carrying blueprint entity tags, fails the decisive test: a real (non-ghost) entity cannot hold tags, so a blueprint made from a drawn design would lose every setting unless the mod armed it in `on_player_setup_blueprint`, as Simple Recursive Blueprints has to.

Supporting choices:

- **The description, not a signal, is the key.** A name is what players read and type, and it carries meaning between saves and between teams. A design number would be exact but means nothing in another save. Descriptions are cut to 500 bytes by the engine, far above any design name.
- **`fast_replaceable_group` is cleared.** The deepcopy keeps the combinator's group, and a marker and a real combinator would fast-replace (destroy) each other.
- **`circuit_wire_max_distance = 0`.** Markers carry nothing worth wiring.
- **Items are hidden, only-in-cursor and spawnable.** The window hands them out; robots can never fetch one, so a marker never becomes a real entity by accident.
- **Marker ghosts never outlive the tick that made them.** A stamp reads its own marker ghosts after `build_blueprint` returns and destroys them. Marker ghosts from anyone else's script, or from a player pasting a blueprint by hand, are destroyed on sight: robots could never build them, and a client check showed each one raising a lasting "no material for construction" alert. Placed one by one (drawing a design in remote view), they stay.
- **Flips are out of v0.1.** Neither prototype records mirroring, and `build_blueprint` has no flip parameter.
