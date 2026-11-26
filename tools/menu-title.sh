#!/bin/sh
# Prove the bold application menu shows the open score's name: launch a test copy on each score given, several times,
# read the menu bar's 2nd item every 2 s for 8 s after the window appears, and refuse any reading that is not the
# score's file name without its extension.
# usage: menu-title.sh <test copy's mscore binary> <launches per score> <score>...
set -eu
[ "$#" -ge 3 ] || {
  echo "usage: menu-title.sh <test copy's mscore binary> <launches per score> <score>..." >&2
  exit 2
}
BINARY=$1
LAUNCHES=$2
shift 2
HERE=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
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
    HOME="${fresh}" TMPDIR="${fresh}" "${BINARY}" "${score}" < /dev/null > /dev/null 2>&1 &
    pid=$!
    deadline=$(($(date +%s) + 60))
    until swift "${HERE}/tools/windows.swift" "${pid}" | grep -q "onscreen=true"; do
      [ "$(date +%s)" -le "${deadline}" ] || {
        echo "${want} launch ${launch}: no window within 60 s"
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
