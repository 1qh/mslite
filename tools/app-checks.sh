#!/bin/sh
# Run the release's app checks on a copy of a built app, on whichever Mac this runs: the 4 gates, or every feature the
# owner uses. Each check launches a test copy under its own bundle identifier, never the owner's app or settings.
# usage: app-checks.sh <app> <score of 2 pages or more> gates|features
set -eu
[ "$#" -eq 3 ] || {
  echo "usage: app-checks.sh <app> <score> gates|features" >&2
  exit 2
}
APP=$1
SCORE=$2
KIND=$3
script_dir=$(dirname -- "$0")
HERE=$(CDPATH='' cd -- "${script_dir}/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "${WORK}"' EXIT
sh "${HERE}/pipeline-copy.sh" "${APP}" "${WORK}/test/mscore.app" org.musescore.MuseScoreLite.test > /dev/null
TEST_BINARY="${WORK}/test/mscore.app/Contents/MacOS/mscore"
case "${KIND}" in
  gates)
    sh "${HERE}/window-check.sh" "${TEST_BINARY}" "${SCORE}"
    sh "${HERE}/net-check.sh" "${TEST_BINARY}" "${SCORE}"
    sh "${HERE}/export-check.sh" "${TEST_BINARY}" "${SCORE}"
    sh "${HERE}/tools/fresh-launch.sh" "${TEST_BINARY}" "${SCORE}"
    ;;
  features)
    DRIVE_PANELS="Palettes,Layout,Properties,Selection filter,History,Navigator,Timeline,Mixer,Percussion" \
      sh "${HERE}/tools/drive-play.sh" "${TEST_BINARY}" "${SCORE}" "${WORK}/panels" 2
    sh "${HERE}/tools/navigator-click.sh" "${TEST_BINARY}" "${SCORE}" "${WORK}/click"
    sh "${HERE}/tools/menu-title.sh" "${TEST_BINARY}" 3 "${SCORE}"
    (cd "${HERE}" && .venv/bin/python -m tools.remember_probe "${TEST_BINARY}" "${SCORE}" && .venv/bin/python -m tools.metronome_pick "${TEST_BINARY}" "${SCORE}")
    sh "${HERE}/tools/isolation-check.sh" "${TEST_BINARY}" "${SCORE}"
    sh "${HERE}/tools/keyboard-check.sh" "${TEST_BINARY}" "${SCORE}" "${WORK}/keys"
    ;;
  *)
    echo "unknown check kind ${KIND}: gates or features" >&2
    exit 2
    ;;
esac
# the copy registered itself with Launch Services when it ran; unregister it so the owner's scores never open in it
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "${WORK}/test/mscore.app" 2> /dev/null || true
