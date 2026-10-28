#!/usr/bin/env bash
# Multiplayer join test. A headless server runs a world that starts growing
# by itself (dev/mods/seb-mp-world); once the mod's queue handler is armed, a
# graphical client joins over localhost, on a private X display
# (dev/vdisplay.sh; FACTORIO_DISPLAY=desktop shows it on your screen). A join
# refused as "mod event handlers are not identical", a desync or a script
# error fails the run.
#   usage: dev/run-mp.sh [join-after-seconds] [stay-seconds]
set -uo pipefail
FACTORIO="${FACTORIO:-$HOME/factorio-2.1/bin/x64/factorio}"
DEV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DEV_DIR/.." && pwd)"
RUN="$REPO/.run/mp"
JOIN_AFTER="${1:-20}"
STAY="${2:-30}"
PORT=34297
# shellcheck source=vdisplay.sh
. "$DEV_DIR/vdisplay.sh"
[ -d "$RUN" ] && vdisplay_stop "$RUN"
rm -rf "$RUN"; mkdir -p "$RUN/mods" "$RUN/server" "$RUN/client"
ln -s "$REPO" "$RUN/mods/self-expanding-blueprints"
ln -s "$DEV_DIR/mods/seb-mp-world" "$RUN/mods/seb-mp-world"
cat > "$RUN/mods/mod-list.json" <<JSON
{ "mods": [
  { "name": "base", "enabled": true }, { "name": "elevated-rails", "enabled": false },
  { "name": "quality", "enabled": false }, { "name": "space-age", "enabled": false },
  { "name": "self-expanding-blueprints", "enabled": true }, { "name": "seb-mp-world", "enabled": true } ] }
JSON
for side in server client; do
  cat > "$RUN/$side/config.ini" <<INI
[path]
read-data=__PATH__executable__/../../data
write-data=$RUN/$side
[graphics]
full-screen=false
INI
done
cat > "$RUN/server-settings.json" <<JSON
{ "name": "seb-mp-test", "description": "", "visibility": { "public": false, "lan": false },
  "require_user_verification": false, "auto_pause": false, "only_admins_can_pause_the_game": true,
  "autosave_interval": 0, "max_players": 0 }
JSON
"$FACTORIO" --config "$RUN/server/config.ini" --create "$RUN/world.zip" --mod-directory "$RUN/mods" \
  --map-gen-seed 1 > "$RUN/create.log" 2>&1 || { tail -20 "$RUN/create.log"; exit 1; }
"$FACTORIO" --config "$RUN/server/config.ini" --mod-directory "$RUN/mods" --start-server "$RUN/world.zip" \
  --port $PORT --server-settings "$RUN/server-settings.json" > "$RUN/server.log" 2>&1 &
SERVER=$!
echo "server pid=$SERVER, client joins in ${JOIN_AFTER}s"
timeout "$JOIN_AFTER" tail -f /dev/null
vdisplay_start "$RUN" 1280x720 || { kill $SERVER; exit 1; }
"$FACTORIO" --config "$RUN/client/config.ini" --mod-directory "$RUN/mods" --mp-connect "127.0.0.1:$PORT" \
  --window-size 1280x720 > "$RUN/client.log" 2>&1 &
CLIENT=$!
echo "client pid=$CLIENT, staying ${STAY}s"
timeout "$STAY" tail -f /dev/null
kill $CLIENT 2>/dev/null; sleep 1; kill $SERVER 2>/dev/null; sleep 1
kill -9 $CLIENT $SERVER 2>/dev/null; vdisplay_stop "$RUN"
echo "---- server SEB_MP"; grep -h "SEB_MP" "$RUN/server.log" | sed -E 's/^.*SEB_MP /SEB_MP /'
echo "---- join"; grep -hiE "joined the game|connected|mod event handlers|desync|mismatch|refused|Error" "$RUN/server.log" "$RUN/client.log" | head -20
status=0
grep -qiE "mod event handlers are not identical|desync|non-recoverable|stack traceback" "$RUN/server.log" "$RUN/client.log" && status=1
grep -qiE "joined the game" "$RUN/server.log" || { echo "client never joined"; status=1; }
[ $status -eq 0 ] && echo "MP JOIN OK" || echo "MP JOIN FAILED (logs: $RUN)"
exit $status
