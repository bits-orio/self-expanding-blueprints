# Update in place lays the new version over the copy

A copy should follow its design's new version without being torn down and rebuilt, which would empty its machines (Wube forum topic 130518) and leave a gap while robots work.

The new version's stamping copy is built superforced over the copy. A part both versions share stays: a paste over an identical entity keeps it, and its contents, and takes the new settings. A part only the new version has comes as a ghost, tagged as the copy's. A part only the old version had is deconstructed and leaves the copy's record. The copy is then building again, and finishes like any other copy, except that its project already counted it and opened its sockets, so it settles nothing again.

Where to build it is the hard part: blueprint coordinates move when a blueprint is edited, so the old and new versions do not share an origin. Every pair of a built entity and a same-named part of the new version proposes a shift; the shift most pairs agree on wins, and among equal votes the one nearest the copy's own blueprint origin (recorded at stamp time) wins, since a blueprint edited in place usually keeps its coordinates. The resulting build position must be on the design's lattice, or the update is refused as misaligned rather than built half a tile off.

An update is also refused when the new footprint would overlap another copy, or cover a building of anyone else's: superforce would mark it for removal. A design can name a research; when its force finishes it, every copy of the design is updated this way.
