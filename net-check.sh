#!/bin/sh
# Launch the built app on 1 score and refuse when it opens any internet socket within the watch window: the owner's
# build never reaches the internet, and a hidden module's background request is invisible on screen.
# usage: net-check.sh <mscore binary> <score> [seconds]
set -e
# the app alone gets an empty home and its own temp folder, where MuseScore keeps the socket its instances find each
# other by, so it never reads the owner's data or reaches the owner's open app; the shell keeps its own, which
# osascript and quit-app.sh need to address the app
APP_HOME=$(mktemp -d)
BINARY=$1
SCORE=$2
script_dir=$(dirname -- "$0")
sh "${script_dir}/tools/test-app.sh" "${BINARY}" "${SCORE}"
SECONDS_TO_WATCH=${3:-45}
FOUND=$(mktemp)
HOME="${APP_HOME}" TMPDIR="${APP_HOME}" "${BINARY}" "${SCORE}" < /dev/null > /dev/null 2>&1 &
PID=$!
# watch for at least SECONDS_TO_WATCH and at least 1 sample every 2 s of it; a loaded machine samples slower, so the
# watch runs on until it has those samples, up to 4 times as long
MIN_SAMPLES=$((SECONDS_TO_WATCH / 2))
start=$(date +%s)
deadline=$((start + SECONDS_TO_WATCH))
cap=$((start + 4 * SECONDS_TO_WATCH))
samples=0
while :; do
  now=$(date +%s)
  if [ "${now}" -gt "${deadline}" ] && { [ "${samples}" -ge "${MIN_SAMPLES}" ] || [ "${now}" -gt "${cap}" ]; }; then
    break
  fi
  kill -0 "${PID}" 2> /dev/null || {
    echo "the app exited during the network check" >&2
    rm -f "${FOUND}"
    exit 1
  }
  lsof -nP -a -p "${PID}" -i 2> /dev/null | awk 'NR > 1 && $9 !~ /^(127\.0\.0\.1|\[::1\]|localhost|\*)/' >> "${FOUND}" || true
  samples=$((samples + 1))
  sleep 1
done
script_dir=$(dirname "$0")
sh "${script_dir}/quit-app.sh" "${PID}"
# a loaded machine makes each lsof call take seconds, and a window sampled a handful of times proves little
if [ "${samples}" -lt "${MIN_SAMPLES}" ]; then
  echo "only ${samples} samples in $((4 * SECONDS_TO_WATCH)) s, fewer than ${MIN_SAMPLES}: the machine is too loaded to judge the network" >&2
  rm -f "${FOUND}"
  exit 1
fi
if [ -s "${FOUND}" ]; then
  echo "the app opened internet sockets:" >&2
  sort -u "${FOUND}" >&2
  rm -f "${FOUND}"
  exit 1
fi
rm -f "${FOUND}"
now=$(date +%s)
echo "ok (${samples} samples over $((now - start)) s, no internet socket)"
