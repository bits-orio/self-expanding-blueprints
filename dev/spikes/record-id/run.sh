#!/usr/bin/env bash
# Spike: blueprint library records (LuaRecord.record_id and shelf_index).
# Question, results and the recorded lines are in FINDINGS.md beside this
# file. This is the headless part: one run of base freeplay in the game's
# test mode (Factorio 2.1.24 and newer) with the probe mod (this folder),
# which lists the game shelf and the player's shelf at tick 30. The id rules
# themselves need a client and a hand on the mouse: the steps are in
# FINDINGS.md.
#
#   usage: dev/spikes/record-id/run.sh [blueprint-storage-2.dat]
#   FACTORIO=<path>   the Factorio binary (default: the 2.1 install)
#   SPIKE_RUN=<dir>   where the run folder goes (default .run/spikes)
#
# The run gets its own write-data and mod directory under .run/spikes/, so it
# never touches the player's own Factorio config, saves or lock file. With no
# argument that write-data starts empty, so the player's shelf is empty. With
# a blueprint storage file as argument, a copy of it is put into the private
# write-data first, and the run lists the records in it with their ids.
#
# Exit status: 0 the run finished (with no argument: and the lines match
# recorded-headless-2.1.25.txt), 1 it did not finish (failed run, engine or
# Lua error, no "RP DONE"), 2 it finished but the lines differ: the engine
# behaves differently.
set -uo pipefail

FACTORIO="${FACTORIO:-$HOME/factorio-2.1/bin/x64/factorio}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
RUN="${SPIKE_RUN:-$REPO/.run/spikes}/record-id"
STORAGE="${1:-}"
[ -x "$FACTORIO" ] || { echo "no Factorio binary at $FACTORIO (set FACTORIO=)"; exit 1; }
[ -z "$STORAGE" ] || [ -f "$STORAGE" ] || { echo "no such file: $STORAGE"; exit 1; }

rm -rf "$RUN"
mkdir -p "$RUN/mods" "$RUN/userdata"
ln -s "$HERE" "$RUN/mods/rec-probe"
cat > "$RUN/mods/mod-list.json" <<EOF
{
  "mods": [
    { "name": "base", "enabled": true },
    { "name": "elevated-rails", "enabled": false },
    { "name": "quality", "enabled": false },
    { "name": "space-age", "enabled": false },
    { "name": "rec-probe", "enabled": true }
  ]
}
EOF
cat > "$RUN/config.ini" <<EOF
[path]
read-data=__PATH__executable__/../../data
write-data=$RUN/userdata
EOF
[ -n "$STORAGE" ] && cp "$STORAGE" "$RUN/userdata/blueprint-storage-2.dat"

"$FACTORIO" --version | head -n 1
status=0
"$FACTORIO" --config "$RUN/config.ini" --mod-directory "$RUN/mods" \
  --test-scenario base/freeplay --test-ticks 60 --test-arg dump > "$RUN/out.log" 2>&1 || { echo "run failed"; status=1; }
grep -h "RP " "$RUN/out.log" | sed -E 's/^.*: RP /RP /' | tee "$RUN/result.txt"
grep -q "^RP DONE" "$RUN/result.txt" || { echo "missing RP DONE"; status=1; }
errors=$(grep -h -v "RP " "$RUN/out.log" | grep -E "Error|error while|stack traceback|Failed to load mods" || true)
[ -n "$errors" ] && { echo "---- errors"; echo "$errors" | head -20; status=1; }
if [ $status -ne 0 ]; then echo "FAILED (log: $RUN/out.log)"; exit 1; fi

if [ -n "$STORAGE" ]; then echo "DONE (a storage file was given: no comparison)"; exit 0; fi
# The lines from the gui_type list on; the list a joining player triggers
# first says the same thing.
if diff "$HERE/recorded-headless-2.1.25.txt" <(sed -n '/^RP gui_type enum/,$p' "$RUN/result.txt") > "$RUN/diff.txt"; then
  echo "DONE: same lines as recorded-headless-2.1.25.txt"
else
  echo "---- differs from recorded-headless-2.1.25.txt (< recorded, > this run)"
  cat "$RUN/diff.txt"
  echo "DONE: the result differs from recorded-headless-2.1.25.txt"; exit 2
fi
