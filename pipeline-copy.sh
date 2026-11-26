#!/bin/sh
# Copy an installed MuseScoreLite into a separate app under its own bundle identifier, for running as a server.
# macOS sends a file opened from Finder, Launchpad or `open` to any running app with the same bundle identifier,
# so servers run from the installed app take the owner's file and show no window; this copy never shares that id.
# usage: pipeline-copy.sh <installed .app> <destination .app> [bundle identifier, the pipeline's by default]
set -e
FROM=${1:?usage: pipeline-copy.sh <installed .app> <destination .app>}
TO=${2:?usage: pipeline-copy.sh <installed .app> <destination .app>}
ID=${3:-org.musescore.MuseScoreLite.pipeline}
rm -rf "${TO}.new"
ditto "${FROM}" "${TO}.new"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${ID}" "${TO}.new/Contents/Info.plist"
# the copy is a local derivative signed ad hoc, so a quarantine it inherits would make Gatekeeper refuse to open it
xattr -dr com.apple.quarantine "${TO}.new"
codesign --force --deep --sign - "${TO}.new" 2> /dev/null
GOT=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${TO}.new/Contents/Info.plist")
[ "${GOT}" = "${ID}" ] || {
  echo "the copy does not carry ${ID}" >&2
  exit 1
}
rm -rf "${TO}"
mv "${TO}.new" "${TO}"
echo ok
