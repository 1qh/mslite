#!/bin/sh
# Quit an app process the way the user would, so it saves its session cleanly, and kill it only when it does not exit
# within 10 seconds: a killed MuseScore marks its session unclean and asks to restore it on the next launch.
# usage: quit-app.sh <pid>
PID=$1
osascript -l JavaScript -e "ObjC.import('AppKit'); \$.NSRunningApplication.runningApplicationWithProcessIdentifier(${PID}).terminate" > /dev/null 2>&1
deadline=$(($(date +%s) + 10))
while kill -0 "${PID}" 2> /dev/null; do
  now=$(date +%s)
  if [ "${now}" -gt "${deadline}" ]; then
    kill "${PID}" 2> /dev/null
    break
  fi
  sleep 1
done
exit 0
