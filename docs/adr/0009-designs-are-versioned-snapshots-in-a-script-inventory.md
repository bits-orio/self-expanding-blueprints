# Designs are versioned snapshots in a script inventory

A registered blueprint is copied into a slot of its force's script inventory (`game.create_inventory`), beside the stamping copy derived from it. The design no longer depends on the player's own blueprint: editing, moving or deleting that blueprint changes nothing. Registering a blueprint under a name that is taken makes the next version of that design; every instance keeps the version number it was stamped from.

Supporting choices:

- **A failed update changes nothing.** The new version is prepared into its own pair of slots beside the working one, and replaces it only if it can be stamped (calibrated, at most one entry arrow). Otherwise the new slots are cleared and the reason is shown; the working version keeps stamping.
- **Design ids are unique across forces.** One counter (`storage.next_design_id`) numbers every design, so an id held by a player, a GUI tag or the grow tool can never name another force's design. Each library still counts its own designs for default names ("Design 3").
- **Prepared data belongs to the current version only.** Anything a later stamp needs from an older version is recorded on the instance at stamp time: its footprint, its repeat size and its world-space sockets.
- **Libraries go with their force.** A merged force's library and a released Multi-Team Support team's library are dropped, inventory and all.
