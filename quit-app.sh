#!/bin/sh
# Quit an app process the way the user would, so it saves its session cleanly, and kill it only when it does not exit
# within 10 seconds, exiting 3 then: a killed MuseScore marks its session unclean and asks to restore it on the next launch,
# and an app that ignores its quit is holding a modal dialog.
# usage: quit-app.sh <pid>
PID=$1
osascript -l JavaScript -e "ObjC.import('AppKit'); \$.NSRunningApplication.runningApplicationWithProcessIdentifier(${PID}).terminate" > /dev/null 2>&1
deadline=$(($(date +%s) + 10))
while kill -0 "${PID}" 2> /dev/null; do
  now=$(date +%s)
  if [ "${now}" -gt "${deadline}" ]; then
    # only the app's own windows, never the whole screen, which holds whatever else the owner has open
    shots=""
    here=$(dirname -- "$0")
    for id in $(swift "${here}/tools/windows.swift" "${PID}" 2> /dev/null | sed -n 's/.* id=\([0-9]*\).*/\1/p'); do
      shot="${TMPDIR:-/tmp}/quit-app-${PID}-${id}.png"
      screencapture -x -o -l "${id}" "${shot}" 2> /dev/null && shots="${shots} ${shot}"
    done
    echo "quit-app: ${PID} ignored its quit for 10 s and was killed; a modal dialog was holding it; its windows:${shots:- none on screen}" >&2
    kill "${PID}" 2> /dev/null
    exit 3
  fi
  sleep 1
done
exit 0
