# S7: dangOreus

Update 2026-10-26: the "on-ore" refusal below was removed with scripts/compat/dangoreus.lua. The mod keeps no rules of mods it does not integrate with (D42), so under dangOreus a copy whose chest or pole lands on ore is built, loses that part, and shows as incomplete; a probe that denies ore under such parts keeps copies off it. The point markers and the sensor finding stand. This spike's "refused with on-ore" check now fails, as expected.

Question: dangOreus (Mylon) destroys any building but a miner whose box covers ore. What does that do to this mod's markers and growth?

Measured on 2.1.23 headless with dangOreus 2.0.6 enabled on nauvis (this folder's spike mod; run it with the mod and dangOreus linked beside it).

- Markers used to die on ore: they were constant combinators with a 0.7-tile box, and dangOreus kills them on any build event. Markers are now points (an empty collision box, tile_width and tile_height 1), which dangOreus skips: sensors, sockets, plugs, probes, ports and Keep clear now stay on ore. Other mods' ground rules that measure an entity's box skip them too.
- dangOreus cannot destroy ghosts (die() does nothing to an entity without health). A copy's chest or pole ghost on ore survives, robots build it, and dangOreus destroys the real thing on arrival, leaving the copy incomplete. So while dangOreus is active the pre-check refuses such a spot with its own reason, "Only miners may stand on ore here (dangOreus)" (scripts/compat/dangoreus.lua mirrors its exception lists, easy mode included). dangOreus keeps the surfaces it is enabled for private, so the rule applies on every surface while it is active.
- A sensor anywhere on a drill's tiles watches the drill's whole mining area, whatever is under the sensor's own tile, so on a drill half on ore it can sit on either half.

Results: a drill-and-chest design on ore is refused with "on-ore"; a drill with its sensor on ore grows; markers placed on ore survive; an iron chest placed on ore still dies (dangOreus active).
