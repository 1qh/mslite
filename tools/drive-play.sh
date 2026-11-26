#!/bin/sh
# Stage the compiled app beside this Mac's Qt, open a score, press Space to play, and save a screenshot.
# usage: drive-play.sh <score> <screenshot.png>
set -e
# every launch below gets its own temp folder, where MuseScore keeps the socket its instances find each other by, so it
# can never reach a copy of the app the owner has open
TMPDIR=$(mktemp -d)
export TMPDIR
SCORE=${1:?usage: drive-play.sh <score> <screenshot.png>}
SHOT=${2:?usage: drive-play.sh <score> <screenshot.png>}
HERE=$(cd "$(dirname "$0")/.." && pwd)
TEST="${HERE}/../mscore-test"
APP="${TEST}/mscore.app/Contents/MacOS/mscore"
running=$(ps -axo pid=,comm= | awk -v app="${APP}" '$2 == app {print $1}')
[ -z "${running}" ] || sh "${HERE}/quit-app.sh" "${running}"
rsync -a --delete "${HERE}/../mscore-release/applebuild/mscore.app/" "${TEST}/mscore.app/"
for dir in "${HERE}/../mscore-qt/lib" "${HERE}/../mscore-deps/lib"; do
  otool -l "${APP}" | grep -q "path ${dir} " || install_name_tool -add_rpath "${dir}" "${APP}"
done
codesign -f -s - "${APP}" 2> /dev/null
open -n "${TEST}/mscore.app" --args "${SCORE}"
deadline=$(($(date +%s) + 60))
until osascript -e 'tell application "System Events" to tell process "mscore" to count windows' 2> /dev/null | grep -q '^[1-9]'; do
  now=$(date +%s)
  if [ "${now}" -gt "${deadline}" ]; then
    echo "no MuseScoreLite window within 60 s" >&2
    exit 1
  fi
  sleep 1
done
sleep 3
osascript -e 'tell application "System Events" to tell process "mscore" to set frontmost to true' -e 'delay 1' \
  -e 'tell application "System Events" to key code 49'
sleep 5
screencapture -x "${SHOT}"
sips -Z 1400 "${SHOT}" --out "${SHOT}" > /dev/null
echo ok
