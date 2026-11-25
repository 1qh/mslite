#!/bin/sh
# Launch the built app on 1 score and refuse when it opens any internet socket within the watch window: the owner's
# build never reaches the internet, and a hidden module's background request is invisible on screen.
# usage: net-check.sh <mscore binary> <score> [seconds]
set -e
BINARY=$1
SCORE=$2
SECONDS_TO_WATCH=${3:-45}
FOUND=$(mktemp)
"${BINARY}" "${SCORE}" < /dev/null > /dev/null 2>&1 &
PID=$!
deadline=$(($(date +%s) + SECONDS_TO_WATCH))
samples=0
while :; do
  now=$(date +%s)
  [ "${now}" -le "${deadline}" ] || break
  kill -0 "${PID}" 2> /dev/null || {
    echo "the app exited during the network check" >&2
    rm -f "${FOUND}"
    exit 1
  }
  lsof -nP -a -p "${PID}" -i 2> /dev/null | awk 'NR > 1 && $9 !~ /^(127\.0\.0\.1|\[::1\]|localhost|\*)/' >> "${FOUND}" || true
  samples=$((samples + 1))
  sleep 1
done
kill "${PID}" 2> /dev/null || true
if [ -s "${FOUND}" ]; then
  echo "the app opened internet sockets:" >&2
  sort -u "${FOUND}" >&2
  rm -f "${FOUND}"
  exit 1
fi
rm -f "${FOUND}"
echo "ok (${samples} samples, no internet socket)"
