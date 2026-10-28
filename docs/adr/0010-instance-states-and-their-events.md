# Instance states and their events

Every stamp is an instance in one of six states, and every change of state that another mod could act on raises a custom event carrying the instance's id, design, version, force, surface, project and reason.

| State | Meaning | Raised on entry |
|---|---|---|
| `building` | Ghosts, tile ghosts or item requests left | (stamp returned the id) |
| `stalled` | Building, but no progress for `STALL_TICKS` | `on_instance_stalled` |
| `complete` | Nothing left; every stamped entity stands | `on_instance_completed` |
| `incomplete` | Nothing left, but a ghost vanished unbuilt | none |
| `retiring` | Its own ghosts destroyed, its entities and tiles ordered for deconstruction | none |
| `retired` | None of its entities or tiles is left | `on_instance_retired` |

Supporting choices:

- **A stall says why.** When the deadline passes, the reason is `no-network` (no construction robots reach the footprint), `missing-materials` (the network has nothing that could build one of its ghosts) or `no-progress`. Laid tiles and delivered items count as progress.
- **Only a complete instance opens sockets.** An incomplete one releases its project's capacity slot and opens nothing, so growth never continues from a broken copy.
- **A subscriber may retire an instance from its completion event.** The project's slot is freed either way, and the sockets open only if the instance is still complete after the event.
- **Retired records go.** Since D45 a retired instance is forgotten right after `on_instance_retired`, which still finds it, so `get_instance` then answers nil and a save does not grow with every copy a team stamps and removes. One kind stays on record, without its entity references, tiles and sockets: a copy retired for depletion while its project grows or is paused, because growth parents from it; it goes when the project ends.
