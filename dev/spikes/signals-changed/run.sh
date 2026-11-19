#!/usr/bin/env bash
# Spike: LuaEntity.get_signals_changed. Question, results and the recorded
# lines are in FINDINGS.md beside this file. Headless; needs the game's test
# mode (Factorio 2.1.24 and newer).
#
# Two game runs of the probe (this folder is the mod "sa-probe"):
#   alone   the probe mod by itself
#   three   with two more mods polling the same connector every tick, one
#           whose handlers run before the probe's (s0-probe) and one after
#           (sz-probe), both made from bystander.lua
# Each run gets its own write-data and mod directory under .run/spikes/, so
# nothing touches the player's own Factorio config, saves or lock file.
#
#   usage: dev/spikes/signals-changed/run.sh [space-age]
#   FACTORIO=<path>   the Factorio binary (default: the 2.1 install)
#   SPIKE_RUN=<dir>   where the run folder goes (default .run/spikes)
#
# Prints the "SC" lines of both runs, says whether the probe's own lines are
# the same with and without the other mods, and compares the run with three
# mods with recorded-2.1.25.txt (timings and item counts aside).
# Exit status: 0 both runs finished with the recorded result,
# 1 a run did not finish (failed run, engine or Lua error, no "SC SC_DONE"),
# 2 both finished but the lines differ: the engine behaves differently.
set -uo pipefail

FACTORIO="${FACTORIO:-$HOME/factorio-2.1/bin/x64/factorio}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
RUN="${SPIKE_RUN:-$REPO/.run/spikes}/signals-changed"
DLC=false
[ "${1:-}" = "space-age" ] && DLC=true
[ -x "$FACTORIO" ] || { echo "no Factorio binary at $FACTORIO (set FACTORIO=)"; exit 1; }

bystander() { # <mods dir> <name>
  mkdir -p "$1/$2"
  sed "s/@NAME@/$2/" "$HERE/bystander.lua" > "$1/$2/control.lua"
  cat > "$1/$2/info.json" <<EOF
{ "name": "$2", "version": "1.0.0", "title": "SEB spike: get_signals_changed, second mod $2", "author": "seb", "factorio_version": "2.1", "dependencies": ["base"] }
EOF
}

run() { # <label> [extra mod names...]; prints the run's SC lines
  local label="$1" dir="$RUN/$1" extra="" name
  shift
  mkdir -p "$dir/mods" "$dir/userdata"
  ln -s "$HERE" "$dir/mods/sa-probe"
  for name in "$@"; do
    bystander "$dir/mods" "$name"
    extra="$extra    { \"name\": \"$name\", \"enabled\": true },"$'\n'
  done
  cat > "$dir/mods/mod-list.json" <<EOF
{
  "mods": [
    { "name": "base", "enabled": true },
    { "name": "elevated-rails", "enabled": $DLC },
    { "name": "quality", "enabled": $DLC },
    { "name": "space-age", "enabled": $DLC },
$extra    { "name": "sa-probe", "enabled": true }
  ]
}
EOF
  cat > "$dir/config.ini" <<EOF
[path]
read-data=__PATH__executable__/../../data
write-data=$dir/userdata
EOF
  "$FACTORIO" --config "$dir/config.ini" --mod-directory "$dir/mods" \
    --test-scenario sa-probe/probe --test-ticks 300 > "$dir/out.log" 2>&1 || { echo "[$label] run failed"; status=1; }
  grep -h "SC " "$dir/out.log" | sed -E 's/^.*: SC /SC /' > "$dir/sc.txt"
  echo "== $label"; cat "$dir/sc.txt"
  grep -q "SC SC_DONE" "$dir/sc.txt" || { echo "[$label] missing SC SC_DONE"; status=1; }
  errors=$(grep -h -v "SC " "$dir/out.log" | grep -E "Error|error while|stack traceback|Failed to load mods" || true)
  [ -n "$errors" ] && { echo "$errors" | head -20 | sed "s/^/[$label] ERROR: /"; status=1; }
}

rm -rf "$RUN"; mkdir -p "$RUN"
"$FACTORIO" --version | head -n 1
status=0
run alone
run three s0-probe sz-probe
if [ $status -ne 0 ]; then echo "FAILED (logs: $RUN)"; exit 1; fi

# Left out of every comparison: the timings, and the two lines that count the
# game's items (they change with the enabled mods and with new items).
steady() { grep -v "Duration:\|T170 big network\|T172 signals on" "$1"; }

# The probe's own lines must not depend on the other mods.
own() { steady "$1" | grep -v "SC s[0z]-probe "; }
result=0
if diff <(own "$RUN/alone/sc.txt") <(own "$RUN/three/sc.txt") > "$RUN/own-diff.txt"; then
  echo "the probe's own lines are the same alone and with the two other mods"
else
  echo "---- the probe's own lines differ (< alone, > with the two other mods)"; cat "$RUN/own-diff.txt"
  result=2
fi

if diff <(steady "$HERE/recorded-2.1.25.txt") <(steady "$RUN/three/sc.txt") > "$RUN/diff.txt"; then
  echo "the run with three mods gives the same lines as recorded-2.1.25.txt"
else
  echo "---- the run with three mods differs from recorded-2.1.25.txt (< recorded, > this run)"
  cat "$RUN/diff.txt"
  result=2
fi
if [ $result -eq 0 ]; then echo "DONE: same result as recorded"; else echo "DONE: the result differs from the recorded one"; fi
exit $result
