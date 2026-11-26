#!/bin/sh
# Close the app's window with its red close button, then reopen the app the way a Dock click or Launchpad does, and
# report whether the process stayed and whether a window came back.
# usage: close-reopen.sh <app bundle> <score>
# Runs on an empty data folder so the owner's session is untouched; needs no other copy of the app running.
set -eu
[ "$#" -eq 2 ] || {
  echo "usage: close-reopen.sh <app bundle> <score>" >&2
  exit 2
}
APP=$1
SCORE=$2
script_dir=$(dirname -- "$0")
HERE=$(CDPATH='' cd -- "${script_dir}/.." && pwd)
sh "${HERE}/tools/test-app.sh" "${APP}/Contents/MacOS/mscore" "${SCORE}"
FRESH=$(mktemp -d)
windows() { swift "${HERE}/tools/windows.swift" "$1" | awk '$1 == "layer" && $2 == 0 && $4 == "onscreen=true"' | grep -c . || true; }
HOME="${FRESH}" TMPDIR="${FRESH}" "${APP}/Contents/MacOS/mscore" "${SCORE}" < /dev/null > /dev/null 2>&1 &
PID=$!
now=$(date +%s)
deadline=$((now + 60))
while :; do
  window_count=$(windows "${PID}")
  if [ "${window_count}" -ge 1 ]; then
    break
  fi
  now=$(date +%s)
  [ "${now}" -le "${deadline}" ] || {
    echo "no window within 60 s" >&2
    kill "${PID}" 2> /dev/null || true
    exit 1
  }
  sleep 1
done
sleep 5
window_count=$(windows "${PID}")
echo "before close: ${window_count} window"
osascript -e "tell application \"System Events\" to tell (first process whose unix id is ${PID}) to click (first button of window 1 whose subrole is \"AXCloseButton\")" > /dev/null
sleep 5
if kill -0 "${PID}" 2> /dev/null; then
  window_count=$(windows "${PID}")
  echo "after close: process alive, ${window_count} window"
else
  echo "after close: process exited"
fi
if [ -s "${FRESH}/mslite/session" ]; then
  session=$(head -c 300 "${FRESH}/mslite/session"/* 2> /dev/null | tr '\n' ' ')
  echo "session file left: ${session}"
fi
find "${FRESH}/mslite" -mindepth 1 -maxdepth 1 -exec basename {} \; | tr '\n' ' '
echo
HOME="${FRESH}" TMPDIR="${FRESH}" "${APP}/Contents/MacOS/mscore" < /dev/null > /dev/null 2>&1 &
AGAIN=$!
sleep 15
if kill -0 "${AGAIN}" 2> /dev/null; then
  window_count=$(windows "${AGAIN}")
  echo "reopen: process alive, ${window_count} window"
  swift "${HERE}/tools/windows.swift" "${AGAIN}" | grep "onscreen=true" || true
  sh "${HERE}/quit-app.sh" "${AGAIN}" && echo "reopen: quit cleanly" || echo "reopen: ignored its quit, a dialog was holding it"
else
  echo "reopen: process exited by itself"
fi
rm -rf "${FRESH}"
