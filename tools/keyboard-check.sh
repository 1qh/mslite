#!/bin/sh
# Prove the piano keyboard behaves for the owner: opened from the View menu, it stays open after playback pauses, and a
# selected note lights its key in a layer colour, never in grey.
# usage: keyboard-check.sh <test copy's mscore binary> <score> <folder>
set -eu
[ "$#" -eq 3 ] || {
  echo "usage: keyboard-check.sh <test copy's mscore binary> <score> <folder>" >&2
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
trap 'sh "${HERE}/quit-app.sh" "${PID}" > /dev/null 2>&1 || true; rm -rf "${FRESH}"' EXIT
window() { swift "${HERE}/tools/windows.swift" "${PID}" | awk '$1 == "layer" && $2 == 0 && $4 == "onscreen=true"' | head -1; }
now=$(date +%s)
deadline=$((now + 60))
while :; do
  main=$(window)
  [ -z "${main}" ] || break
  now=$(date +%s)
  [ "${now}" -le "${deadline}" ] || {
    echo "no score window within 60 s" >&2
    exit 1
  }
  sleep 1
done
sleep 3
front="tell application \"System Events\" to set frontmost of (first process whose unix id is ${PID}) to true"
menu="tell application \"System Events\" to tell (first process whose unix id is ${PID}) to click menu item \"Piano keyboard\" of menu 1 of menu bar item \"View\" of menu bar 1"
# opening the keyboard moves keyboard focus off the score, so every keystroke below follows a click on an empty spot of
# the score, which gives the score its focus back
size=$(printf '%s\n' "${main}" | awk '{print $3}')
origin=$(printf '%s\n' "${main}" | sed -E 's/.* at=([0-9.]+),([0-9.]+).*/\1 \2/')
spot_x=$(printf '%s %s\n' "${size}" "${origin}" | awk -F'[x ]' '{printf "%d", $3 + $1 * 0.985}')
spot_y=$(printf '%s %s\n' "${size}" "${origin}" | awk -F'[x ]' '{printf "%d", $4 + $2 * 0.9}')
focus() {
  swift "${HERE}/tools/click.swift" "${spot_x}" "${spot_y}"
  sleep 1
}
key() { osascript -e "${front}" -e 'delay 0.5' -e "tell application \"System Events\" to $1" < /dev/null > /dev/null; }
osascript -e "${front}" -e 'delay 1' -e "${menu}" -e 'delay 2' < /dev/null > /dev/null
focus
key "key code 49"
sleep 3
focus
key "key code 49"
sleep 2
id=$(window | sed -E 's/.* id=([0-9]+) .*/\1/')
screencapture -x -o -l "${id}" "${OUT}/paused.png"
focus
key 'keystroke "a" using command down'
sleep 2
screencapture -x -o -l "${id}" "${OUT}/selected.png"
actions=$(grep -a "try call action" "${OUT}/app.log" | sed 's/.*try call action: //' | tr -d '\033' | sed 's/\[0m//' | tr '\n' ' ')
case "${actions}" in
  *"play "*"play "*) ;;
  *)
    echo "the drive did not reach the app: it received ${actions}" >&2
    exit 1
    ;;
esac
"${HERE}/.venv/bin/python" "${HERE}/tools/keyboard_pixels.py" "${OUT}/paused.png" "${OUT}/selected.png"
