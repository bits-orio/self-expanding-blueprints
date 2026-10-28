#!/usr/bin/env bash
# Launch a graphical client on a dev world, isolated from the player's own
# config and saves (private write-data under .run/gui) and from the desktop
# (a private X display, dev/vdisplay.sh). Drive it with dev/gui-drive.sh,
# watch it with "dev/gui-drive.sh watch", stop it with "dev/gui-drive.sh stop".
# Starting again replaces a client still running from the last start.
#   usage: dev/run-gui.sh [space-age]
#   SEB_WORLD=<dev mod>   the world mod to load (default seb-gui-world)
#   SEB_SIZE=<WxH>        client window size (default 1600x900)
#   SEB_UI_SCALE=<n>      interface scale, e.g. 1 or 1.5 (default: the game's automatic scale)
#   FACTORIO_DISPLAY=desktop   open the window on your own screen instead
set -uo pipefail
FACTORIO="${FACTORIO:-$HOME/factorio-2.1/bin/x64/factorio}"
DEV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DEV_DIR/.." && pwd)"
RUN="$REPO/.run/gui"
SIZE="${SEB_SIZE:-1600x900}"
# shellcheck source=vdisplay.sh
. "$DEV_DIR/vdisplay.sh"
[ -f "$RUN/pid" ] && "$DEV_DIR/gui-drive.sh" stop
DLC=false; [ "${1:-}" = "space-age" ] && DLC=true
rm -rf "$RUN/mods" "$RUN/world.zip"; mkdir -p "$RUN/mods" "$RUN/userdata"
ln -s "$REPO" "$RUN/mods/self-expanding-blueprints"
WORLD="${SEB_WORLD:-seb-gui-world}"
ln -s "$DEV_DIR/mods/$WORLD" "$RUN/mods/$WORLD"
cat > "$RUN/mods/mod-list.json" <<JSON
{ "mods": [
  { "name": "base", "enabled": true }, { "name": "elevated-rails", "enabled": $DLC },
  { "name": "quality", "enabled": $DLC }, { "name": "space-age", "enabled": $DLC },
  { "name": "self-expanding-blueprints", "enabled": true }, { "name": "$WORLD", "enabled": true } ] }
JSON
cat > "$RUN/config.ini" <<INI
[path]
read-data=__PATH__executable__/../../data
write-data=$RUN/userdata
[graphics]
full-screen=false
INI
# A fixed interface scale, to see the GUI as a player at that scale does.
if [ -n "${SEB_UI_SCALE:-}" ]; then
  printf '[interface]\nui-scale-mode=manual-pixels\ncustom-ui-scale=%s\n' "$SEB_UI_SCALE" >> "$RUN/config.ini"
fi
"$FACTORIO" --config "$RUN/config.ini" --create "$RUN/world.zip" --mod-directory "$RUN/mods" --map-gen-seed 1 > "$RUN/create.log" 2>&1 \
  || { tail -20 "$RUN/create.log"; exit 1; }
vdisplay_start "$RUN" "$SIZE" || exit 1
# No sound: a client on a private display must not play on the desktop's speakers.
nohup "$FACTORIO" --config "$RUN/config.ini" --mod-directory "$RUN/mods" --load-game "$RUN/world.zip" \
  --window-size "$SIZE" --disable-audio > "$RUN/client.log" 2>&1 &
echo $! > "$RUN/pid"; echo "pid=$(cat "$RUN/pid") display=$DISPLAY"
