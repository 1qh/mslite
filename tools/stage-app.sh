#!/bin/sh
# Stage the compile Mac's built app on this Mac as a runnable test copy, the way release.sh prepares it for its first
# gates: fetch it, point its library search at this Mac's Qt and dependencies, sign it ad hoc, and copy it under the
# test bundle identifier. For driving a build before it is packaged.
# usage: stage-app.sh <rsync source of the built .app> <staging folder> <Qt folder> <deps folder>
# The source is the INSTALLED app (the compile Mac's applebuild/mscore.app after a build-only release), never the
# build tree's app: only the install step puts the QML modules inside the bundle, and without them no window opens.
# Prints the test copy's executable.
set -eu
[ "$#" -eq 4 ] || {
  echo "usage: stage-app.sh <rsync source of the built .app> <staging folder> <Qt folder> <deps folder>" >&2
  exit 2
}
FROM=$1
STAGE=$2
QT=$3
DEPS=$4
HERE=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
mkdir -p "${STAGE}/built.app"
rsync -a --delete "${FROM}/" "${STAGE}/built.app/" < /dev/null
BINARY="${STAGE}/built.app/Contents/MacOS/mscore"
for dir in "${QT}/lib" "${DEPS}/lib"; do
  otool -l "${BINARY}" | grep -q "path ${dir} " || install_name_tool -add_rpath "${dir}" "${BINARY}"
done
codesign --force --sign - "${BINARY}" 2> /dev/null
sh "${HERE}/pipeline-copy.sh" "${STAGE}/built.app" "${STAGE}/test.app" org.musescore.MuseScoreLite.test > /dev/null
echo "${STAGE}/test.app/Contents/MacOS/mscore"
