#!/bin/sh
# Launch the built app on 1 score and refuse when its main window fails to load: a QML type a switched-off module
# owns leaves the app running with no window, which no command-line check sees.
# usage: window-check.sh <mscore binary> <score>
set -e
# every launch below gets its own temp folder, where MuseScore keeps the socket its instances find each other by, so it
# can never reach a copy of the app the owner has open
TMPDIR=$(mktemp -d)
export TMPDIR
BINARY=$1
SCORE=$2
LOGS="${HOME}/mslite/logs"
RUNNING=$(ps -axo comm=)
case "
${RUNNING}
" in *"
${BINARY}
"*)
  echo "another ${BINARY} is running; it would take the score and leave this launch without a log" >&2
  exit 1
  ;;
*) ;;
esac
MARK=$(mktemp)
sleep 1
"${BINARY}" "${SCORE}" < /dev/null > /dev/null 2>&1 &
PID=$!
deadline=$(($(date +%s) + 60))
verdict=""
while [ -z "${verdict}" ]; do
  now=$(date +%s)
  if [ "${now}" -gt "${deadline}" ]; then
    verdict="timeout"
    break
  fi
  log=$(find "${LOGS}" -name '*.log' -newerBm "${MARK}" 2> /dev/null | head -1)
  if [ -n "${log}" ]; then
    if grep -q "Failed to load main qml" "${log}"; then
      verdict="failed"
    elif modified=$(/usr/bin/stat -f %m "${log}") && [ "$((now - modified))" -ge 10 ]; then
      verdict="ok"
    fi
  fi
  [ -z "${verdict}" ] && ! kill -0 "${PID}" 2> /dev/null && verdict="exited"
  sleep 1
done
sh "$(dirname "$0")/quit-app.sh" "${PID}"
rm -f "${MARK}"
case ${verdict} in
  ok) echo ok ;;
  failed)
    echo "main window failed to load:" >&2
    grep -m1 "Failed to load main qml" "${log}" | sed 's/\\n/\n/g' >&2
    exit 1
    ;;
  *)
    echo "window check ${verdict} before the log went quiet" >&2
    exit 1
    ;;
esac
