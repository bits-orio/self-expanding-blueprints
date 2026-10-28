# Ore sensors decide when a copy grows on

A finished copy opens its sockets at once, so growth runs as fast as the robots. After playing v0.1 the author asked for mining designs that grow on only once the ore under them is used up, and noted that the area that matters is often smaller than a drill's whole mining area.

An ore sensor is a marker drawn into a design, a constant combinator underneath like sockets and plugs (ADR-0001), so its settings travel with every blueprint. A finished copy of a design with sensors opens its sockets only once no ore is left in any area its sensors watch. The area is the mining area of the drill a sensor sits on; or, with the signal R set in the sensor, the square of 2R + 1 tiles around it, which can be smaller or larger than a drill's; or else the sensor's own tile. A copy whose areas are already empty when it finishes opens at once. While it waits, the overlay draws its watched areas, and the project counts it, so a project does not finish while copies still wait.

Retiring copies whose ore has run out is a separate project option, `retire_depleted`: a finished copy is retired once none of its drills can mine anything left in its mining area, after a short delay so its output can drain. Keeping the two apart lets a design grow on early without removing the old copy, or remove dry copies without waiting to grow.

Both are event-driven. `on_resource_depleted` fires when a resource runs out; an index of watched areas by chunk names the copies to look at, and a check a little later counts what is left (the depleted resource is removed right after the event). Nothing polls.
