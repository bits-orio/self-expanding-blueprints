#!/usr/bin/env bash
# The blueprint library lines of dev/PLAYTEST.md in a real client, driven by
# mouse and keyboard on its private display (never by script, save for the
# log lines): a labelled blueprint is put on a shelf of the library (B), held
# and added as a design with the window's add button, renamed by typing in
# the record's own window and saved, then held again.
#   usage: dev/library-check.sh [game|mine]   the shelf: Game blueprints (default) or My blueprints
#   FACTORIO=<binary>   another engine; before 2.1.25 a record has no id, so the
#                       renamed entry must be a new design and closing it must say nothing
# Screenshots and the SEB_LIB log lines go to .run/library/<shelf>-<engine>/.
# Exit status is non-zero when the design, its version or its link to the
# entry are not what that engine should give. The chat lines are for the eye:
# 3-noticed.png and 5-updated.png.
# Coordinates are for the 1920x1080 window at the automatic interface scale.
set -uo pipefail
DEV="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=harness-lib.sh
. "$DEV/harness-lib.sh"
[ "${FACTORIO_DISPLAY:-}" = desktop ] && { echo "library-check drives the client's display: never the desktop" >&2; exit 1; }
SHELF="${1:-game}"
case "$SHELF" in
  game) TAB="1089 387" ;;
  mine) TAB="978 387" ;;
  *) echo "unknown shelf: $SHELF (expected game or mine)"; exit 1 ;;
esac
OUT="$REPO/.run/library/$SHELF-$ENGINE_FULL"; rm -rf "$OUT"; mkdir -p "$OUT"
G="$DEV/gui-drive.sh"
INVENTORY_SLOT="512 378"   # the first slot of the Character grid
SHELF_SLOT="966 456"       # the first slot of the shelf
LABEL_PENCIL="440 215"     # the pencil beside the label "Solar cell" in the record's window
SAVE_BUTTON="1482 797"     # Save blueprint
ADD_BUTTON="960 471"       # the add button of the Self-Expanding Blueprints window

trap '"$G" stop > /dev/null 2>&1' EXIT
# A client's own data outlives a run: My blueprints as an earlier run left
# it, or files of a newer engine that an older one stops at with a dialog.
"$G" stop > /dev/null 2>&1; rm -rf "$REPO/.run/gui/userdata"
GUI_SIZE=1920x1080 "$DEV/run-gui.sh" base || exit 1
sleep 4   # the world hands the blueprint over a second after the player is created
export DISPLAY; DISPLAY="$(cat "$REPO/.run/gui/display")"
LOG="$REPO/.run/gui/userdata/factorio-current.log"

click() { "$G" click "$@"; sleep 0.7; }
key() { "$G" key "$@"; sleep 0.7; }
shot() { "$G" shot "$OUT/$1.png"; }
# The designs, their links to library entries and what the hand holds.
state() {
  "$G" lua "__self-expanding-blueprints__ local p=game.player local lib=storage.libraries[p.force.index] local out={} for _,d in pairs(lib and lib.designs or {}) do local l=d.record out[#out+1]=d.name..' v'..d.version..' link='..(l and (l.key..' label='..l.label..' at v'..l.version..' noticed='..tostring(l.seen~=nil)) or 'none') end local r=p.cursor_record local ok,k=pcall(function() return r.shelf_index..':'..r.record_id end) log('SEB_LIB $1 designs=['..table.concat(out,'; ')..'] holds='..tostring(r and r.label)..' key='..tostring(r and ok and k))"
}
open_shelf() { key b; click $TAB; }
hold_entry() { open_shelf; click $SHELF_SLOT; key Escape; }

# The blueprint from the hand into the inventory, then onto the shelf.
"$G" lua "local p=game.player p.get_main_inventory().clear() p.clear_cursor()"
open_shelf; click $INVENTORY_SLOT; click $SHELF_SLOT; shot 1-stored; key Escape

# Held from the library and added with the window's button.
hold_entry; key shift+alt+g; sleep 0.5; shot 2-add-button
click $ADD_BUTTON; shot 2-added; state added
key shift+alt+g; key q

# Renamed in the record's own window: the pencil, the new label typed, Enter, Save.
open_shelf; click $SHELF_SLOT 3; shot 3-record; click $LABEL_PENCIL
xdotool key ctrl+a; xdotool type --delay 60 "Solar cell 2"; sleep 0.3; shot 3-typing
xdotool key Return; sleep 0.5
click $SAVE_BUTTON; sleep 0.5; shot 3-noticed; state renamed
key Escape

# Held again: the add button offers the design's next version, or a new design.
hold_entry; key shift+alt+g; sleep 0.5; shot 4-held-again; state held
click $ADD_BUTTON; shot 5-updated; state pressed

grep -h "SEB_LIB" "$LOG" | sed -E 's/^.*SEB_LIB /SEB_LIB /' > "$OUT/states.txt"
cat "$OUT/states.txt"
status=0
want() { # <state> <pattern> <what>
  grep "^SEB_LIB $1 " "$OUT/states.txt" | grep -qE "$2" || { echo "FAIL $1: $3"; status=1; }
}
want added 'designs=\[Solar cell v1 ' "the held entry did not become the design Solar cell"
if harness_engine_at_least 2.1.25; then
  want added 'link=[0-9]+:[0-9]+ label=Solar cell at v1 noticed=false' "the design does not remember its entry"
  want renamed 'label=Solar cell 2 at v1 noticed=true' "the renamed entry was not noticed when its window closed"
  want held 'holds=Solar cell 2 ' "the renamed entry is not in the hand"
  want pressed 'designs=\[Solar cell v2 link=[0-9]+:[0-9]+ label=Solar cell 2 at v2' "the renamed entry did not become version 2 of its design"
else
  want added 'designs=\[Solar cell v1 link=none\]' "a record without an id was remembered"
  want renamed 'designs=\[Solar cell v1 link=none\]' "closing the record changed a design"
  want pressed 'Solar cell 2 v1 link=none' "the renamed entry did not register by its label"
  want pressed 'Solar cell v1 link=none' "the first design did not stay as it was"
fi
grep -hE "Error|stack traceback" "$LOG" | grep -v "SEB_LIB" | head -5 | grep . && status=1
[ "$status" -eq 0 ] && echo "LIBRARY CHECK OK ($SHELF shelf, Factorio $ENGINE_FULL): $OUT" || echo "LIBRARY CHECK FAILED: $OUT"
exit "$status"
