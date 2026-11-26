#!/bin/sh
# Refuse a launch of any app but a test copy, and give the test copy empty settings: settings live under the bundle
# identifier, so only a copy under org.musescore.MuseScoreLite.test can be launched without touching the owner's.
# usage: test-app.sh <mscore binary>      make a test copy with: pipeline-copy.sh <app> <copy> org.musescore.MuseScoreLite.test
set -eu
TEST_ID=org.musescore.MuseScoreLite.test
plist="$(dirname -- "$1")/../Info.plist"
id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${plist}" 2> /dev/null || true)
[ "${id}" = "${TEST_ID}" ] || {
  echo "refused: ${1} is ${id:-no app}, not a test copy under ${TEST_ID}; launching it would use that app's settings" >&2
  exit 1
}
defaults delete "${TEST_ID}" > /dev/null 2>&1 || true
