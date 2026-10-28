#!/usr/bin/env bash
# Records the portal GIFs (docs/media/*.gif): a client on a private display
# (dev/run-gui.sh with the seb-media-world dev mod), driven with xdotool on
# that display only, recorded with ffmpeg's x11grab and cut into GIFs whose
# interface parts play at 1x and building parts faster.
#   usage: dev/record-media.sh [scene ...]   default: plan grow fill remove turn sockets
# "plan" clicks its project's row, so it runs while that row is the first of
# its design's; "remove" takes copies off the field "fill" built.
# Coordinates assume the 1280x720 window and interface scale 1 started here,
# with the window pinned at (340, 100): change the window and they move.
# Needs ffmpeg. Raw takes and their marks stay in .run/media.
set -uo pipefail
DEV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DEV_DIR/.." && pwd)"
OUT="$REPO/.run/media"; mkdir -p "$OUT" "$REPO/docs/media"
DRIVE="$DEV_DIR/gui-drive.sh"
[ "${FACTORIO_DISPLAY:-}" = desktop ] && { echo "record-media drives the client's display: never the desktop" >&2; exit 1; }
SCENES=("$@"); [ ${#SCENES[@]} -eq 0 ] && SCENES=(plan grow fill remove turn sockets)

SEB_WORLD=seb-media-world SEB_SIZE=1280x720 SEB_UI_SCALE=1 "$DEV_DIR/run-gui.sh" > /dev/null || exit 1
trap '"$DRIVE" stop > /dev/null 2>&1' EXIT
for _ in $(seq 1 60); do grep -q 'Loading map' "$REPO/.run/gui/client.log" 2>/dev/null && break; sleep 2; done
sleep 10
export DISPLAY; DISPLAY=$(cat "$REPO/.run/gui/display")

CX=640; CY=360; T0=0; SCENE=""
lua() { "$DRIVE" lua "$1" > /dev/null 2>&1; }
# Lua in the mod's own environment: window (W), registry (R), tool (T), the
# player (p), their grow options (o) and state (s).
seb() {
  lua "__self-expanding-blueprints__ local P=package.loaded local W=P['__self-expanding-blueprints__/scripts/gui/window.lua'] local R=P['__self-expanding-blueprints__/scripts/core/registry.lua'] local T=P['__self-expanding-blueprints__/scripts/tool.lua'] local p=game.player local o=R.grow_options(p.index) local s=R.player(p.index) s.window_location={x=340,y=100} $1 p.clear_console()"
}
stage() { xdotool key q; lua "remote.call('seb-media','go','$1') game.player.teleport({$2,$3}) game.player.zoom=$4 game.player.clear_console()"; }
park() { xdotool mousemove "$1" "$2"; CX=$1; CY=$2; }
smove() { # glide to x y in n steps
  local n=${3:-18} i
  for i in $(seq 1 "$n"); do
    xdotool mousemove $(( CX + ($1 - CX) * i / n )) $(( CY + ($2 - CY) * i / n )); sleep 0.022
  done
  CX=$1; CY=$2
}
press() { xdotool mousedown "${1:-1}"; sleep 0.12; xdotool mouseup "${1:-1}"; }
drag() { # drag button x1 y1 x2 y2
  smove "$2" "$3" 25; sleep 0.5; xdotool mousedown "$1"; sleep 0.2; smove "$4" "$5" 45; sleep 0.4; xdotool mouseup "$1"
}
mark() { echo "$1 $(echo "$(date +%s.%N) - $T0" | bc)" >> "$OUT/$SCENE.marks"; }
at() { awk -v k="$1" -v d="$2" '$1 == k { print $2 + d }' "$OUT/$SCENE.marks"; }
rec_start() {
  SCENE=$1; rm -f "$OUT/$SCENE.marks"
  ffmpeg -loglevel error -y -f x11grab -draw_mouse 1 -framerate 30 -video_size 1280x720 -i "$DISPLAY.0+0,0" \
    -c:v libx264 -preset ultrafast -qp 0 "$OUT/$SCENE.mkv" > "$OUT/$SCENE.log" 2>&1 &
  REC=$!; sleep 0.4; T0=$(date +%s.%N)
}
rec_stop() { kill -INT "$REC"; wait "$REC" 2> /dev/null; }

# gif <name> <filter inputs> <segments>: each segment "input start end speed".
gif() {
  local name=$1 inputs=$2; shift 2
  local graph="" labels="" i=0 seg
  for seg in "$@"; do
    set -- $seg
    graph+="[$1:v]trim=$2:$3,setpts=(PTS-STARTPTS)/$4[s$i];"; labels+="[s$i]"; i=$((i + 1))
  done
  ffmpeg -loglevel error -y $inputs -filter_complex "${graph}${labels}concat=n=$i:v=1,\
tpad=stop_mode=clone:stop_duration=1.5,fps=10,scale=960:-1:flags=lanczos,split[a][b];\
[a]palettegen=max_colors=96:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
    "$REPO/docs/media/$name.gif"
  echo "docs/media/$name.gif $(du -h "$REPO/docs/media/$name.gif" | cut -f1)"
}

scene_grow() { # the window, Grow, one click: a field that stops at the lake
  stage grow 14 16 0.5
  seb 'o.max_instances=12 o.fast=false o.more=false o.dry_run=false s.selected_design=1 s.design_open=false W.close(p)'
  park 330 560; sleep 0.8; rec_start grow
  sleep 1.0; xdotool key shift+alt+g; sleep 1.0
  smove 480 300; sleep 0.4; press; sleep 1.2
  smove 600 412; sleep 0.5; press; sleep 0.3
  smove 776 152 30; sleep 1.2; press; sleep 0.5; mark placed
  smove 330 560 25; sleep 20; rec_stop
  gif grow "-i $OUT/grow.mkv" "0 0.6 $(at placed 0.8) 1" "0 $(at placed 0.8) $(at placed 12.8) 3"
}
scene_fill() { # Fill an area, dragged from its bottom-right corner
  stage fill -2 298 0.5
  seb 'o.max_instances=12 o.fast=true o.more=false o.dry_run=false s.selected_design=1 s.design_open=true W.open(p)'
  park 1060 600; sleep 0.8; rec_start fill
  sleep 1.2; smove 802 412; sleep 0.5; press; sleep 0.5
  drag 1 1184 504 736 216; mark dragged
  sleep 0.4; smove 330 560 25; sleep 12; rec_stop
  gif fill "-i $OUT/fill.mkv" "0 0.6 $(at dragged 0.8) 1" "0 $(at dragged 0.8) $(at dragged 5.8) 2"
}
scene_remove() { # a right-drag retires the middle columns of fill's field
  stage fill -2 298 0.5
  seb 'o.fast=true o.more=false o.dry_run=false s.selected_design=1 s.design_open=true W.open(p)'
  park 1060 600; sleep 0.8; rec_start remove
  sleep 1.2; smove 802 412; sleep 0.5; press; sleep 0.5
  drag 3 1056 488 864 232; mark dragged
  sleep 0.4; smove 330 560 25; sleep 10; rec_stop
  gif remove "-i $OUT/remove.mkv" "0 0.6 $(at dragged 0.5) 1" "0 $(at dragged 0.5) $(at dragged 3.5) 1"
}
scene_turn() { # the same road as drawn, turned (R) and flipped (V)
  stage turn 2 596 0.5
  seb 'o.max_instances=8 o.fast=true o.more=false o.dry_run=false s.selected_design=2 s.design_open=true W.close(p) T.give(p)'
  park 640 560; sleep 0.8; rec_start turn
  sleep 0.8; smove 104 256 30; sleep 1.0; press; sleep 2.0
  xdotool key shift+alt+g; sleep 0.8; smove 602 458; sleep 0.4; press; sleep 0.5
  xdotool key r; sleep 0.6; smove 840 264 30; sleep 1.0; press; sleep 2.0
  xdotool key shift+alt+g; sleep 0.8; smove 602 458; sleep 0.4; press; sleep 0.5
  xdotool key v; sleep 0.6; smove 104 448 30; sleep 1.0; press; sleep 0.5; mark flipped
  smove 640 560 25; sleep 8; rec_stop
  gif turn "-i $OUT/turn.mkv" "0 2.5 $(at flipped 0.4) 1" "0 $(at flipped 0.4) $(at flipped 3.4) 2"
}
scene_sockets() { # a road that grows through its socket and hangs cells off its side
  stage sockets 14 912 0.5
  seb 'o.max_instances=false o.fast=true o.more=false o.dry_run=false s.selected_design=2 W.close(p) T.give(p)'
  park 640 560; sleep 0.8; rec_start sockets
  sleep 0.8; smove 328 160 30; sleep 1.4; press; sleep 0.5; mark placed
  smove 640 560 25; sleep 10; rec_stop
  gif sockets "-i $OUT/sockets.mkv" "0 0.5 $(at placed 0.6) 1" "0 $(at placed 0.6) $(at placed 6.4) 1.5"
}
scene_plan() { # Plan only lays outlines; the row's green check grows it for real
  stage plan 290 8 0.5
  seb 'o.max_instances=12 o.fast=false o.more=true o.dry_run=false s.selected_design=1 s.design_open=true W.open(p)'
  park 330 560; sleep 0.8; rec_start plan1
  sleep 1.2; smove 506 484; sleep 0.6; press; sleep 1.0
  smove 600 550; sleep 0.5; press; sleep 0.4
  smove 760 120 30; sleep 1.2; press; sleep 0.5; mark placed
  smove 330 560 25; sleep 2; rec_stop
  local placed; placed=$(at placed 0.8)
  rec_start plan2
  sleep 0.8; xdotool key shift+alt+g; sleep 1.0
  smove 789 677 30; sleep 0.8; press; sleep 1.0; mark built
  smove 920 120 30; sleep 0.4; press; sleep 0.3
  smove 330 560 25; sleep 10; rec_stop
  gif plan "-i $OUT/plan1.mkv -i $OUT/plan2.mkv" "0 0.5 $placed 1" \
    "1 0.4 $(at built 1.6) 1" "1 $(at built 1.6) $(at built 7.4) 2"
}

lua 'local v=game.player.game_view_settings v.show_research_info=false v.show_minimap=false v.show_alert_gui=false v.show_side_menu=false game.player.clear_console()'
for scene in "${SCENES[@]}"; do "scene_$scene" || exit 1; done
