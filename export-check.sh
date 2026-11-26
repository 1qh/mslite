#!/bin/sh
# Ask the built app for every format the sheet pipeline exports, and refuse when any comes back missing or empty: a
# module the lean build switches off fails only when the pipeline first asks for its format.
# usage: export-check.sh <mscore binary> <score>
set -e
# the app alone gets an empty home and its own temp folder, where MuseScore keeps the socket its instances find each
# other by, so it never reads the owner's data or reaches the owner's open app; the shell keeps its own, which
# osascript and quit-app.sh need to address the app
APP_HOME=$(mktemp -d)
BINARY=$1
SCORE=$2
sh "$(dirname -- "$0")/tools/test-app.sh" "${BINARY}" "${SCORE}"
OUT=$(mktemp -d)
failed=""
for format in pdf mpos mid musicxml mscz; do
  if ! HOME="${APP_HOME}" TMPDIR="${APP_HOME}" "${BINARY}" -o "${OUT}/check.${format}" "${SCORE}" < /dev/null > /dev/null 2>&1 || [ ! -s "${OUT}/check.${format}" ]; then
    failed="${failed} ${format}"
  fi
done
rm -rf "${OUT}"
if [ -n "${failed}" ]; then
  echo "the app cannot export:${failed}" >&2
  exit 1
fi
echo ok
