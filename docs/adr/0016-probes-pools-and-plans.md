# Probes, pools and plans

Three ways a project can try things without stamping them.

**Probes.** A probe is a marker that states what must be true on its tile before a copy is built there. Like every marker it is a constant combinator, so its predicate is its signals, which travel with the blueprint: no signal means some resource, an entity signal names a resource, an item or fluid signal names the resources that yield it, the fluid signal water asks for water, and the signal "deny" negates. A failed probe closes the socket with the reason "probe".

**Pools.** A labelled blueprint book becomes a pool under its label when it is added: its designs, in order. A socket whose description names the pool tries each design in turn, with every check a stamp makes; the first that is stamped or waits at a gate wins, and when none fits the first one's reason closes the socket. A count reached closes it for all. Designs keep their own names, so a design can be in a pool and be grown on its own.

**Plans.** A dry run is a project that plans instead of stamping. A spot that passes every check becomes a planned copy, a footprint and its sockets with no entities, which counts as finished at once, so the whole plan unfolds as outlines before any ghost exists. Planned copies block only their own plan. A plan stops at 400 copies when it has no count, so a fill of open land cannot grow without end. Building a finished plan starts a new project with the same seed, rules and gates, which grows the same copies for real.
