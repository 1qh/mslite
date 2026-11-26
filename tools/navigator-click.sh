#!/bin/sh
# Prove a click in the floating Navigator moves the score view: zoom a test copy's score in, open the Navigator, capture the score
# window twice with no click (the control: the capture alone must not change), click low on the Navigator's right half,
# where a 2-page score's 2nd page sits, and capture again; the view must have moved.
# usage: navigator-click.sh <test copy's mscore binary> <score of 2 pages or more> <folder>
set -eu
[ "$#" -eq 3 ] || {
  echo "usage: navigator-click.sh <test copy's mscore binary> <score of 2 pages or more> <folder>" >&2
  exit 2
}
BINARY=$1
SCORE=$2
OUT=$3
script_dir=$(dirname -- "$0")
HERE=$(CDPATH='' cd -- "${script_dir}/.." && pwd)
sh "${HERE}/tools/test-app.sh" "${BINARY}" "${SCORE}"
mkdir -p "${OUT}"
FRESH=$(mktemp -d)
HOME="${FRESH}" TMPDIR="${FRESH}" "${BINARY}" "${SCORE}" < /dev/null > "${OUT}/app.log" 2>&1 &
PID=$!
window() { swift "${HERE}/tools/windows.swift" "${PID}" | awk -v layer="$1" '$1 == "layer" && $2 == layer && $4 == "onscreen=true"' | head -1; }
now=$(date +%s)
deadline=$((now + 60))
while :; do
  main=$(window 0)
  [ -z "${main}" ] || break
  now=$(date +%s)
  [ "${now}" -le "${deadline}" ] || {
    echo "no score window within 60 s" >&2
    sh "${HERE}/quit-app.sh" "${PID}" || true
    exit 1
  }
  sleep 1
done
trap 'sh "${HERE}/quit-app.sh" "${PID}" > /dev/null 2>&1 || true' EXIT
front="tell application \"System Events\" to set frontmost of (first process whose unix id is ${PID}) to true"
# zoom the score in first, so the view holds part of page 1 and a click on page 2 has somewhere to move it
osascript -e "${front}" -e 'delay 2' \
  -e 'tell application "System Events" to repeat 4 times' -e 'keystroke "=" using command down' -e 'delay 0.5' -e 'end repeat' \
  -e "tell application \"System Events\" to tell (first process whose unix id is ${PID}) to click menu item \"Navigator\" of menu 1 of menu bar item \"View\" of menu bar 1" \
  -e 'delay 3' < /dev/null > /dev/null
navigator=$(window 3)
[ -n "${navigator}" ] || {
  echo "the Navigator opened no floating window" >&2
  sh "${HERE}/quit-app.sh" "${PID}" || true
  exit 1
}
main_id=$(printf '%s\n' "${main}" | sed -E 's/.* id=([0-9]+) .*/\1/')
size=$(printf '%s\n' "${navigator}" | awk '{print $3}')
origin=$(printf '%s\n' "${navigator}" | sed -E 's/.* at=([0-9.]+),([0-9.]+).*/\1 \2/')
x=$(printf '%s %s\n' "${size}" "${origin}" | awk -F'[x ]' '{printf "%d", $3 + $1 * 0.75}')
y=$(printf '%s %s\n' "${size}" "${origin}" | awk -F'[x ]' '{printf "%d", $4 + $2 * 0.75}')
screencapture -x -o -l "${main_id}" "${OUT}/before.png"
sleep 2
screencapture -x -o -l "${main_id}" "${OUT}/still.png"
osascript -e "${front}" -e 'delay 1' < /dev/null > /dev/null
swift "${HERE}/tools/click.swift" "${x}" "${y}"
sleep 2
# the Navigator covers most of the score window, which macOS may leave undrawn, so close it before the capture
osascript -e "${front}" -e 'delay 1' \
  -e "tell application \"System Events\" to tell (first process whose unix id is ${PID}) to click menu item \"Navigator\" of menu 1 of menu bar item \"View\" of menu bar 1" \
  -e 'delay 2' < /dev/null > /dev/null
screencapture -x -o -l "${main_id}" "${OUT}/after.png"
quit=0
sh "${HERE}/quit-app.sh" "${PID}" || quit=$?
rm -rf "${FRESH}"
# a QML binding that names something absent logs a TypeError or ReferenceError and leaves its control dead
if grep -E 'qrc:[^ ]+\.qml:[0-9]+.*(TypeError|ReferenceError|Unable to assign)' "${OUT}/app.log" > "${OUT}/qml-errors.txt"; then
  echo "QML errors in the app's log:" >&2
  sed 's/.*| //' "${OUT}/qml-errors.txt" | sort | uniq -c >&2
  exit 1
fi
cmp -s "${OUT}/before.png" "${OUT}/still.png" || {
  echo "the score window changed with no click, so this capture cannot judge a click" >&2
  exit 1
}
cmp -s "${OUT}/before.png" "${OUT}/after.png" && {
  echo "a click at ${x},${y} in the Navigator left the score view where it was" >&2
  exit 1
}
echo "ok (a click at ${x},${y} in the Navigator moved the score view; the control capture held still; quit status ${quit})"
