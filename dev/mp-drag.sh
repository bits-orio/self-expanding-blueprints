#!/usr/bin/env bash
# The area tool's drag preview in multiplayer, with or without latency. A
# headless server runs dev/mods/seb-drag-world; one client joins on a private
# X display at 1920x1080 holding the area tool, through dev/udp-delay.py when
# latency is asked for (a network whose round trip takes that many ticks),
# and the mouse is driven with xdotool on that display: a drag in steps, a
# drag called off with Q, two flicks and a smooth drag released on the move.
# The world logs every selection event and every change of the preview with
# its tick, on the server and on the client; dev/mp-drag-report.py reads both
# logs and the times of the mouse moves and says how far the preview trails
# the pointer, whether it ever outlives a drag, who sees it, and whether the
# two simulations agree.
#   usage: dev/mp-drag.sh [round-trip-ticks]   (default 0; 30 is half a second)
# Output in .run/mp-drag/<ticks>/: report.txt, marks.txt, shots/, the logs.
# Exit status is non-zero when the client never joins, on a desync, a script
# error, or a failed check of the report.
# Needs Factorio 2.1.22 or newer (the engine tells of a drag in flight from
# there on), xdotool and imagemagick.
set -uo pipefail
DEV="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=harness-lib.sh
. "$DEV/harness-lib.sh"
# shellcheck source=vdisplay.sh
. "$DEV/vdisplay.sh"
[ "${FACTORIO_DISPLAY:-}" = desktop ] && { echo "mp-drag drives the client's display: never the desktop" >&2; exit 1; }
LAT="${1:-0}"
RUN="$REPO/.run/mp-drag/$LAT"
SIZE=1920x1080
# Long enough for a move to show at this latency before the next one.
PAUSE="$(python3 -c "print(0.6 + 1.5 * $LAT / 60)")"
[ -d "$RUN" ] && vdisplay_stop "$RUN"
rm -rf "$RUN"; mkdir -p "$RUN/server" "$RUN/client" "$RUN/shots"
harness_config "$RUN/server"
harness_config "$RUN/client" graphics
harness_stage "$RUN" base "$DEV/mods/seb-drag-world" || exit 1
cat > "$RUN/server-settings.json" <<JSON
{ "name": "$MOD-mp-drag", "description": "", "visibility": { "public": false, "lan": false },
  "require_user_verification": false, "auto_pause": false, "only_admins_can_pause_the_game": true,
  "autosave_interval": 0, "max_players": 0 }
JSON
"$FACTORIO" --config "$RUN/server/config.ini" --create "$RUN/world.zip" --mod-directory "$RUN/mods" \
  --map-gen-seed 1 > "$RUN/create.log" 2>&1 || { tail -20 "$RUN/create.log"; exit 1; }

SERVER=""; CLIENT=""; RELAY=""
cleanup() {
  kill $CLIENT $SERVER $RELAY 2>/dev/null
  for _ in $(seq 1 20); do
    kill -0 $CLIENT 2>/dev/null || kill -0 $SERVER 2>/dev/null || break
    sleep 0.25
  done
  # Only the two games are waited for: the display is this shell's child too.
  kill -9 $CLIENT $SERVER 2>/dev/null; wait $CLIENT $SERVER 2>/dev/null; vdisplay_stop "$RUN"
}
trap cleanup EXIT
"$FACTORIO" --config "$RUN/server/config.ini" --mod-directory "$RUN/mods" --start-server "$RUN/world.zip" \
  --port "$(harness_port_request)" --server-settings "$RUN/server-settings.json" > "$RUN/server.log" 2>&1 &
SERVER=$!
PORT="$(harness_bound_port "$RUN/server.log")" || { echo "server never hosted"; tail -20 "$RUN/server.log"; exit 1; }
JOIN=$PORT
if [ "$LAT" -gt 0 ]; then
  python3 "$DEV/udp-delay.py" "$PORT" "$(python3 -c "print($LAT * 1000 / 60 / 2)")" "$RUN/relay.port" &
  RELAY=$!
  for _ in $(seq 1 50); do [ -s "$RUN/relay.port" ] && break; sleep 0.1; done
  JOIN="$(cat "$RUN/relay.port")" || exit 1
fi
vdisplay_start "$RUN" "$SIZE" || exit 1
"$FACTORIO" --config "$RUN/client/config.ini" --mod-directory "$RUN/mods" --mp-connect "127.0.0.1:$JOIN" \
  --window-size "$SIZE" --disable-audio > "$RUN/client.log" 2>&1 &
CLIENT=$!
echo "server pid=$SERVER port=$PORT, client pid=$CLIENT display=$DISPLAY joins at port $JOIN, round trip $LAT ticks"
LOG="$RUN/client/userdata/factorio-current.log"
waited() { # <seconds> <pattern> <file>
  for _ in $(seq 1 "$1"); do
    grep -q "$2" "$3" 2>/dev/null && return 0
    kill -0 "$CLIENT" 2>/dev/null || return 1
    sleep 1
  done
  return 1
}
waited 180 "joined the game" "$RUN/server.log" || { echo "client never joined"; tail -20 "$RUN/client.log"; exit 1; }
waited 60 "SEB_DRAG .* tool p=1 given=true" "$LOG" || { echo "the client never held the area tool"; exit 1; }
# The log's lines carry seconds since the log was opened: its birth time
# turns them into wall time, to set against the times of the mouse moves.
date -d "$(stat -c %w "$LOG")" +%s.%N > "$RUN/log-opened"
date -d "$(stat -c %w "$RUN/server/userdata/factorio-current.log")" +%s.%N > "$RUN/server-log-opened"
# A client joins with 32 ticks of latency ("Initialized Synchronizer ...
# latency(32)" in its log) and the server brings that down to what the
# network needs over the next seconds: moves made before then trail by more.
sleep 20

W=""
for id in $(xdotool search --pid "$CLIENT" 2>/dev/null); do
  case "$(xdotool getwindowname "$id" 2>/dev/null)" in Factorio*) W=$id ;; esac
done
[ -n "$W" ] || { echo "client window not found"; exit 1; }
xdotool windowraise "$W"; xdotool windowfocus --sync "$W"; sleep 0.3

# Each action is marked with the wall time right after it was sent.
mark() { echo "$(date +%s.%N) $*" >> "$RUN/marks.txt"; }
mv()   { xdotool mousemove --window "$W" "$1" "$2"; mark "move $1 $2"; }
down() { xdotool mousedown 1; mark down; }
up()   { xdotool mouseup 1; mark up; }
shot() { mark "shot $1"; import -window root "$RUN/shots/$1.png"; }
steps() { # <x1> <y1> <x2> <y2> <count> <seconds between>
  local i
  for i in $(seq 1 "$5"); do mv $(( $1 + ($3 - $1) * i / $5 )) $(( $2 + ($4 - $2) * i / $5 )); sleep "$6"; done
}
# A screenshot this soon after an action is inside the latency window.
EARLY=0.08

mark "drag stepped"   # eight moves, each given time to show
mv 800 400; sleep 0.5; down; sleep "$PAUSE"
steps 800 400 1120 640 4 "$PAUSE"
mv 1200 700; sleep "$EARLY"; shot stepped-1-moved; sleep "$PAUSE"; shot stepped-2-settled
steps 1200 700 1440 880 3 "$PAUSE"
up; sleep "$EARLY"; shot stepped-3-released; sleep "$PAUSE"; shot stepped-4-after
mark "end"

mark "drag q"         # called off with Q while the button is down
mv 300 150; sleep 0.5; down; sleep 0.2
steps 300 150 700 380 4 0.1; sleep "$PAUSE"; shot q-1-dragging
xdotool key q; mark "key q"; sleep "$EARLY"; shot q-2-pressed; sleep "$PAUSE"; shot q-3-after
up; sleep "$PAUSE"; sleep 1.5   # the world hands the tool back
mark "end"

mark "drag flick"     # pressed, moved and released faster than a frame
mv 300 700; sleep 0.5
xdotool mousedown 1 mousemove --window "$W" 700 1000 mouseup 1; mark flicked
sleep "$EARLY"; shot flick-1-released; sleep "$PAUSE"; sleep 0.5; shot flick-2-after
mark "end"

mark "drag quick"     # three moves a hundredth of a second apart, then released
mv 1500 120; sleep 0.5; down
steps 1500 120 1860 330 3 0.01
up; sleep "$EARLY"; shot quick-1-released; sleep "$PAUSE"; sleep 0.5; shot quick-2-after
mark "end"

mark "drag smooth"    # a hand's drag, released while still moving
mv 1000 100; sleep 0.5; down; sleep 0.1
steps 1000 100 1400 330 40 0.025
up; sleep "$EARLY"; shot smooth-1-released; sleep "$PAUSE"; sleep 0.5; shot smooth-2-after
mark "end"

sleep 4   # time for the server to compare the two simulations
cleanup; trap - EXIT
python3 "$DEV/mp-drag-report.py" "$RUN" "$LAT" | tee "$RUN/report.txt"
exit "${PIPESTATUS[0]}"
