# Gates hold the head of the frontier; sockets no robots reach are parked

A project grows breadth-first from a first-in, first-out frontier of open sockets. Three gates hold the frontier at its head without closing anything: capacity (at most `MAX_BUILDING`, by default two, of the project's copies under construction at once), missing materials (the network covering the next copy lacks an item it costs) and chunks (the map under it is still generating). Capacity reopens on an instance's completion, and chunks on `on_chunk_generated` for the project's surface; items arriving in a network have no engine event, so a materials wait retries on a timer.

A socket that no construction robots reach is different: that is a property of its place, not of the project. Holding the head for it would stop every other socket forever, so it is parked on its own list, the rest of the frontier goes on, and parked sockets return to the back of the frontier every `NETWORK_RETRY` ticks (ten seconds). Coverage has no engine event either: roboports gain power and robots silently. A project keeps growing while parked sockets remain, and the window says why.

Supporting choices:

- **Capacity is per project.** Growth runs as fast as the robots, and two copies in flight keep a project moving without flooding the network; the remote interface can set `max_building`.
- **Missing materials stay global.** Every copy of the project costs the same items, so if the head cannot be supplied, neither can the rest.
- **`on_materials_missing` fires on a change, not on every retry.** It is raised when a project starts waiting for an item or the item changes, and fires again only after a stamp succeeded.
- **v0.1 draws arrows, not outlines of the next stamps.** Open sockets show as arrows, waiting ones with their reason, and closed ones as crosses with theirs.
