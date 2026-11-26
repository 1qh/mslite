#!/bin/sh
# Open a score in a test copy of the app on an empty data folder, press Space to play, and save screenshots of every
# on-screen window the app shows: the score window first, then each floating panel.
# usage: drive-play.sh <test copy's mscore binary> <score> <screenshot folder> [seconds of playback before the shot]
# DRIVE_PANELS names View menu items to open first, comma separated, such as Mixer,Properties.
set -eu
[ "$#" -ge 3 ] || {
  echo "usage: drive-play.sh <test copy's mscore binary> <score> <screenshot folder> [seconds]" >&2
  exit 2
}
BINARY=$1
SCORE=$2
SHOTS=$3
PLAY_SECONDS=${4:-6}
HERE=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
sh "${HERE}/tools/test-app.sh" "${BINARY}"
# the app alone gets its own temp folder, where MuseScore keeps the socket its instances find each other by, so it
# can never reach a copy of the app the owner has open, and an empty home, so its data folder starts empty; the
# osascript calls keep the shell's own, or System Events loses the process's menu bar
FRESH=$(mktemp -d)
mkdir -p "${SHOTS}"
HOME="${FRESH}" TMPDIR="${FRESH}" "${BINARY}" "${SCORE}" < /dev/null > /dev/null 2>&1 &
PID=$!
# the score window sits at layer 0 and floating panels at layer 3
onscreen() { swift "${HERE}/tools/windows.swift" "${PID}" | awk '$1 == "layer" && ($2 == 0 || $2 == 3) && $4 == "onscreen=true"'; }
deadline=$(($(date +%s) + 60))
until [ -n "$(onscreen)" ]; do
  [ "$(date +%s)" -le "${deadline}" ] || {
    echo "no window within 60 s" >&2
    kill "${PID}" 2> /dev/null || true
    exit 1
  }
  sleep 1
done
sleep 5
# the menu bar exists only for the frontmost app, so bring it forward before any menu click
osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is ${PID}) to true" \
  -e 'delay 2' > /dev/null
# open each View menu item DRIVE_PANELS names (comma separated), so floating panels show as windows of their own
printf '%s\n' "${DRIVE_PANELS:-}" | tr ',' '\n' | while IFS= read -r panel; do
  [ -n "${panel}" ] || continue
  osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is ${PID}) to true" \
    -e 'delay 1' -e "tell application \"System Events\" to tell (first process whose unix id is ${PID}) to click menu item \"${panel}\" of menu 1 of menu bar item \"View\" of menu bar 1" < /dev/null > /dev/null
  sleep 2
done
osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is ${PID}) to true" \
  -e 'delay 1' -e 'tell application "System Events" to key code 49' > /dev/null
sleep "${PLAY_SECONDS}"
count=0
for id in $(onscreen | sed -n 's/.* id=\([0-9]*\).*/\1/p'); do
  count=$((count + 1))
  screencapture -x -o -l "${id}" "${SHOTS}/window-${count}.png"
  sips -Z 1600 "${SHOTS}/window-${count}.png" --out "${SHOTS}/window-${count}.png" > /dev/null
done
quit=0
sh "${HERE}/quit-app.sh" "${PID}" || quit=$?
rm -rf "${FRESH}"
[ "${count}" -gt 0 ] || {
  echo "no on-screen window to capture" >&2
  exit 1
}
echo "ok (${count} windows captured in ${SHOTS}; quit status ${quit})"
