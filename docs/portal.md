# Self-Expanding Blueprints

> Grow a factory from your own blueprints.

[![Discord](https://img.shields.io/badge/Discord-join%20the%20server-5865F2?logo=discord&logoColor=white)](https://discord.gg/tWz4FT74pH) [![GitHub](https://img.shields.io/badge/GitHub-source-181717?logo=github&logoColor=white)](https://github.com/bits-orio/self-expanding-blueprints)

Register a blueprint, click the map, and robots keep building copies of it until water, cliffs or your rules stop them. Every copy is tracked: it reports when its robots are done, and you can remove exactly that copy and nothing next to it. A from-scratch reimagining of Recursive Blueprints, with the recursion drawn into the blueprints themselves.

![One click with the design in hand, and robots build copies until the lake stops them](https://raw.githubusercontent.com/bits-orio/self-expanding-blueprints/main/docs/media/grow.gif)

## Status

Version 0.2.0 is the first release, for Factorio 2.1. The window, growing, plans and the copies panel have been played in a game client. A headless test suite (base and Space Age) and a multiplayer join test back them. Ore sensors, probes, pools, updates in place, circuit requests and space platforms are covered by the headless tests and have had less play in a real game. The remote interface for other mods is a draft and can change before 1.0. Bug reports are welcome in the discussion tab or on [GitHub](https://github.com/bits-orio/self-expanding-blueprints/issues).

## Quick start

1. Open the window from the shortcut bar or press SHIFT + ALT + G.
2. Hold a blueprint and press **Add “your blueprint” as a design**.
3. Click the design in the list to open its page, and pick the directions to grow toward.
4. Press **Grow**, then click the map. The first copy goes down where its ghosts were, and growth carries on from there, 4 copies unless you set another number.
5. To fill a rectangle instead, press **Fill an area** and drag one.

## Features

### Growing

- Grow puts the design in your hand: turn or flip it like any blueprint, click, and every copy follows.
- Fill an area by dragging a rectangle, and right-drag to remove copies, exactly what each one built.
- Draw a socket where the next copy goes and a plug where it attaches; a socket can name another design or a book of designs.
- Plan a project as outlines before any ghost exists, then grow it for real.
- Every copy goes down whole or not at all, and a blocked spot says why.

![Turn or flip the design in hand, and its growth turns or flips with it](https://raw.githubusercontent.com/bits-orio/self-expanding-blueprints/main/docs/media/turn.gif)

![A road whose socket grows it east and hangs a solar cell off each piece](https://raw.githubusercontent.com/bits-orio/self-expanding-blueprints/main/docs/media/sockets.gif)

### Markers and mining

- Ore sensors make copies wait until the ore runs out, and dry copies can be removed.
- Probes keep copies to the right ground, and Keep clear tiles leave a lane empty between copies.

### Tracking and control

- Each copy knows when its robots are done, and a project says why it waits, with its recent history on hover.
- Copies follow their design: update them in place, or when a research finishes.
- The blueprint builder drives it all from circuits with named signals and a request, accepted, done handshake.

## Compatibility

Needs Factorio 2.1. Space Age is optional, and projects grow on space platforms too. Designs, projects and copies belong to a force, so every Multi-Team Support team grows its own factory.

Server admins get map settings for each team's projects, plans, designs, builders and copies in flight, a share of server time for each team and a cap on the whole server's, so no team can slow the game for the others for long. One big piece of work, such as registering a design at the size limit, can still make a single tick long.

Land Title Registry refuses copies outside the land your team holds, Negative Space's plain markers count as Keep clear, and AI Agent Bridge gets read tools for projects and designs.

## Works with

Part of the MTS family:

- [Multi-Team Support](https://mods.factorio.com/mod/multi-team-support) (optional): each team keeps its own designs and growth.
- [Blueprint Primer](https://mods.factorio.com/mod/BlueprintPrimer): primed designs keep their item requests, and a copy counts as done only once they are delivered.
- [Brave New MTS](https://mods.factorio.com/mod/brave-new-mts): everything works from remote view, with no chest to fill.

## Links

- Source: [github.com/bits-orio/self-expanding-blueprints](https://github.com/bits-orio/self-expanding-blueprints)
- Full guide: [README on GitHub](https://github.com/bits-orio/self-expanding-blueprints/blob/main/README.md)
- Discord: [discord.gg/tWz4FT74pH](https://discord.gg/tWz4FT74pH)

## Credits

Self-Expanding Blueprints is a full rewrite with its own design; no code is reused. The idea of a factory that builds itself comes from Recursive Blueprints (Doc, justarandomgeek, DaveMcW) and Recursive Blueprints+ (FoxLBA), and some ideas were borrowed from Simple Recursive Blueprints (Qweasd123tg), PersistantBlueprints (mrvn), blueprint-deconstruction-markers (Elwin), Negative Space (Rycieos), Construction Probe (Eketek) and AutoDeconstruct (mindmix). With thanks to all of them.

## Development

Developed with AI coding assistants alongside human review and in-game testing. MIT licensed. Contributions are welcome: see the [repository](https://github.com/bits-orio/self-expanding-blueprints).
