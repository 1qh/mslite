#!/bin/sh
# Launch the app on 1 score with an empty data folder, as on a first launch, and refuse when its main window fails to
# load, shows any window beside the score, or ignores its quit, which a modal dialog causes: the first launch opens
# straight onto the score.
# usage: fresh-launch.sh <mscore binary> <score>
# Runs the app with HOME pointed at a new empty folder, so its data folder (~/mslite) starts empty and the owner's stays
# untouched; give it a binary whose bundle identifier no running app shares, or macOS hands the score to that app.
set -eu
# every launch below gets its own temp folder, where MuseScore keeps the socket its instances find each other by, so it
# can never reach a copy of the app the owner has open
TMPDIR=$(mktemp -d)
export TMPDIR
[ "$#" -eq 2 ] || {
  echo "usage: fresh-launch.sh <mscore binary> <score>" >&2
  exit 2
}
BINARY=$1
SCORE=$2
HERE=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
FRESH=$(mktemp -d)
HOME="${FRESH}" "${BINARY}" "${SCORE}" < /dev/null > /dev/null 2>&1 &
PID=$!
deadline=$(($(date +%s) + 60))
log=""
while [ -z "${log}" ]; do
  now=$(date +%s)
  [ "${now}" -le "${deadline}" ] || break
  log=$(find "${FRESH}/mslite/logs" -name '*.log' 2> /dev/null | head -1)
  kill -0 "${PID}" 2> /dev/null || break
  sleep 1
done
if [ -z "${log}" ]; then
  kill "${PID}" 2> /dev/null || true
  rm -rf "${FRESH}"
  echo "the app wrote no log within 60 s" >&2
  exit 1
fi
sleep 20
failed=$(grep -c "Failed to load main qml" "${log}" || true)
windows=$(swift "${HERE}/tools/windows.swift" "${PID}" | awk '$1 == "layer" && $2 == 0 && $4 == "onscreen=true"')
count=$(printf '%s' "${windows}" | grep -c . || true)
quit=0
sh "${HERE}/quit-app.sh" "${PID}" || quit=$?
rm -rf "${FRESH}"
if [ "${quit}" -ne 0 ]; then
  echo "the app ignored its quit: a dialog was open" >&2
  exit 1
fi
if [ "${failed}" -gt 0 ]; then
  echo "the main window failed to load" >&2
  exit 1
fi
if [ "${count}" -ne 1 ]; then
  echo "the first launch shows ${count} windows, not the score alone:" >&2
  printf '%s\n' "${windows}" >&2
  exit 1
fi
echo "ok (1 window: ${windows})"
