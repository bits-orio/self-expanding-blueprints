# The window lists projects in v0.1

DESIGN.md puts "the project window" in a later milestone. v0.1 ships a projects list in the main window anyway: one row per project with its state, progress, why it waits or stopped, and pause, resume and stop. Without it a player had no way to stop a runaway fill, or to learn why growth stopped, short of reading the map.

Rows update in place and are redrawn only when what they show changes. In multiplayer a click names its element, and a click on an element destroyed in the meantime is lost, so a list rebuilt at every growth step swallowed clicks. Pause and resume are two buttons shown in turn rather than one button that flips: a click already in flight then never does the opposite of what was clicked. The full project window (history, blocked sockets, per-socket detail) stays a later milestone.
