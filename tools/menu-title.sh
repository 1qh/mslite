#!/bin/sh
# Prove the bold application menu shows the open score's name: launch a test copy on each score given, several times,
# read the menu bar's 2nd item every 2 s for 8 s after the window appears, and refuse any reading that is not the
# score's file name without its extension.
# usage: menu-title.sh <test copy's mscore binary> <launches per score> <score>...
# MENU_TITLE_LOGS, when set, names a folder that keeps each launch's own output.
set -eu
[ "$#" -ge 3 ] || {
  echo "usage: menu-title.sh <test copy's mscore binary> <launches per score> <score>..." >&2
  exit 2
}
BINARY=$1
LAUNCHES=$2
shift 2
script_dir=$(dirname -- "$0")
HERE=$(CDPATH='' cd -- "${script_dir}/.." && pwd)
sh "${HERE}/tools/test-app.sh" "${BINARY}" "$@"
wrong=0
readings=0
for score in "$@"; do
  want=$(basename "${score}" .mscz)
  launch=0
  while [ "${launch}" -lt "${LAUNCHES}" ]; do
    launch=$((launch + 1))
    sh "${HERE}/tools/test-app.sh" "${BINARY}"
    fresh=$(mktemp -d)
    log=/dev/null
    [ -z "${MENU_TITLE_LOGS:-}" ] || log="${MENU_TITLE_LOGS}/${want}-${launch}.log"
    HOME="${fresh}" TMPDIR="${fresh}" "${BINARY}" "${score}" < /dev/null > "${log}" 2>&1 &
    pid=$!
    now=$(date +%s)
    deadline=$((now + 60))
    # the window appears before the score has loaded, and until it has the title is rightly the app's own name, so the
    # readings start once the score window carries the score's name
    until swift "${HERE}/tools/windows.swift" "${pid}" | grep "onscreen=true" | grep -qF " ${want}"; do
      now=$(date +%s)
      [ "${now}" -le "${deadline}" ] || {
        echo "${want} launch ${launch}: no window showing the score within 60 s"
        wrong=$((wrong + 1))
        break
      }
      sleep 1
    done
    osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is ${pid}) to true" \
      -e 'delay 1' > /dev/null 2>&1 || true
    seen=""
    for _ in 1 2 3 4; do
      sleep 2
      title=$(osascript -e "tell application \"System Events\" to tell (first process whose unix id is ${pid}) to get name of menu bar item 2 of menu bar 1" 2>&1 || true)
      readings=$((readings + 1))
      seen="${seen} ${title}"
      [ "${title}" = "${want}" ] || wrong=$((wrong + 1))
    done
    echo "${want} launch ${launch}:${seen}"
    sh "${HERE}/quit-app.sh" "${pid}" || echo "${want} launch ${launch}: ignored its quit"
    rm -rf "${fresh}"
  done
done
[ "${wrong}" -eq 0 ] || {
  echo "${wrong} of ${readings} readings were not the score's name" >&2
  exit 1
}
echo "ok (${readings} readings, every one the open score's name)"
