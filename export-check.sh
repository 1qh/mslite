#!/bin/sh
# Ask the built app for every format the sheet pipeline exports, and refuse when any comes back missing or empty: a
# module the lean build switches off fails only when the pipeline first asks for its format.
# usage: export-check.sh <mscore binary> <score>
set -e
BINARY=$1
SCORE=$2
OUT=$(mktemp -d)
failed=""
for format in pdf mpos mid musicxml mscz; do
  if ! "${BINARY}" -o "${OUT}/check.${format}" "${SCORE}" < /dev/null > /dev/null 2>&1 || [ ! -s "${OUT}/check.${format}" ]; then
    failed="${failed} ${format}"
  fi
done
rm -rf "${OUT}"
if [ -n "${failed}" ]; then
  echo "the app cannot export:${failed}" >&2
  exit 1
fi
echo ok
