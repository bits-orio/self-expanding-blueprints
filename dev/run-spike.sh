#!/usr/bin/env bash
# Headless spike runner. A spike is a standalone dev mod under dev/spikes/<name>
# whose on_init lays out its cases and logs SEB_SPIKE lines; later checks can
# run from on_nth_tick while --benchmark advances the save so robots fly.
#
#   usage: dev/run-spike.sh <name> [ticks] [space-age]
#
#   FACTORIO=<path>   the Factorio binary (default: the 2.1 install)
#
# Each spike gets an isolated mod directory and write-data directory under
# .run/spikes/<name>/, so several spikes can run at once and none of them
# touches the player's own Factorio config, saves or lock file.
#
# Prints the SEB_SPIKE lines, then any engine or Lua errors. Exit status is
# non-zero on a failed Factorio run or an error in the logs.
set -uo pipefail

FACTORIO="${FACTORIO:-$HOME/factorio-2.1/bin/x64/factorio}"
DEV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DEV_DIR/.." && pwd)"

NAME="${1:?usage: dev/run-spike.sh <name> [ticks] [space-age]}"
TICKS="${2:-600}"
DLC=false
[ "${3:-}" = "space-age" ] && DLC=true

SPIKE_SRC="$DEV_DIR/spikes/$NAME"
[ -f "$SPIKE_SRC/info.json" ] || { echo "no spike at $SPIKE_SRC"; exit 2; }
MOD_NAME="$(sed -nE 's/.*"name": *"([^"]+)".*/\1/p' "$SPIKE_SRC/info.json" | head -n 1)"

RUN="$REPO/.run/spikes/$NAME"
rm -rf "$RUN"
mkdir -p "$RUN/mods" "$RUN/userdata"
ln -s "$SPIKE_SRC" "$RUN/mods/$MOD_NAME"

cat > "$RUN/mods/mod-list.json" <<EOF
{
  "mods": [
    { "name": "base", "enabled": true },
    { "name": "elevated-rails", "enabled": $DLC },
    { "name": "quality", "enabled": $DLC },
    { "name": "space-age", "enabled": $DLC },
    { "name": "$MOD_NAME", "enabled": true }
  ]
}
EOF

cat > "$RUN/config.ini" <<EOF
[path]
read-data=__PATH__executable__/../../data
write-data=$RUN/userdata
EOF

status=0
"$FACTORIO" --config "$RUN/config.ini" --create "$RUN/spike.zip" --mod-directory "$RUN/mods" \
  --map-gen-seed 1 > "$RUN/create.log" 2>&1 || { echo "--create failed"; status=1; }
if [ $status -eq 0 ]; then
  "$FACTORIO" --config "$RUN/config.ini" --benchmark "$RUN/spike.zip" --benchmark-ticks "$TICKS" \
    --mod-directory "$RUN/mods" > "$RUN/bench.log" 2>&1 || { echo "--benchmark failed"; status=1; }
fi

touch "$RUN/create.log" "$RUN/bench.log"
grep -h "SEB_SPIKE" "$RUN/create.log" "$RUN/bench.log" | sed -E 's/^.*SEB_SPIKE /SEB_SPIKE /'
errors=$(grep -h -v "SEB_SPIKE" "$RUN/create.log" "$RUN/bench.log" \
  | grep -E "Error|error while|stack traceback|Failed to load mods" || true)
if [ -n "$errors" ]; then
  echo "---- errors"
  echo "$errors" | head -40
  status=1
fi
if [ $status -ne 0 ]; then
  echo "---- log tails ($RUN)"
  tail -n 25 "$RUN/create.log" "$RUN/bench.log"
fi
exit $status
