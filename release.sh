#!/bin/sh
# Build the head of upstream MuseScore's current release branch with every patch, for Apple Silicon, sign, notarize, and publish it.
# Needs the Developer ID Application identity in the keychain, and MSCORE_SECRETS naming the folder that holds
# asc-api.p8, asc-api-key-id.txt and asc-api-issuer-id.txt (an App Store Connect API key, for notarization).
# MSCORE_BUILD_ONLY=1 stops after the compile (the compile Mac); MSCORE_PACKAGE_ONLY=1 skips it; MSCORE_APP_FROM, naming
# an rsync source such as host:path/mscore.app, packages the app built there and implies MSCORE_PACKAGE_ONLY.
# MSCORE_CHECK_SCORE names a score of 2 pages or more: every gate and feature check opens it, the Navigator click included.
set -e
# a shell reads its script as it runs, so a pull or an edit mid-run would splice the run: run from a private copy
if [ -z "${MSLITE_SCRIPT_HOME:-}" ]; then
  MSLITE_SCRIPT_HOME=$(cd "$(dirname "$0")" && pwd)
  export MSLITE_SCRIPT_HOME
  copy=$(mktemp)
  cp "$0" "${copy}"
  exec sh "${copy}" "$@"
fi
trap 'rm -f "$0"' EXIT
HERE=${MSLITE_SCRIPT_HOME}
unset MSLITE_SCRIPT_HOME
FORK=${MSCORE_FORK:-1qh/MuseScore}
SRC=${MSCORE_RELEASE_SRC:-${HERE}/../mscore-release}
DEPS=${MSCORE_DEPS:-${HERE}/../mscore-deps}
QT=${MSCORE_QT:-${HERE}/../mscore-qt}
PATCHES="serve piano-playback packaging flat-picker debloat"
UPSTREAM=https://github.com/musescore/MuseScore.git
LATEST=$(gh api repos/musescore/MuseScore/releases/latest --jq .tag_name)
BRANCH=${MSCORE_BRANCH:-$(echo "${LATEST#v}" | cut -d. -f1-2)}
HEAD_SHA=$(git ls-remote "${UPSTREAM}" "refs/heads/${BRANCH}" | cut -f1)
[ -n "${HEAD_SHA}" ] || {
  echo "upstream has no branch ${BRANCH}" >&2
  exit 1
}
SHORT=$(echo "${HEAD_SHA}" | cut -c1-8)
COMMITS=$(($(echo "${PATCHES}" | wc -w) + 1))
STALE=0
for patch in ${PATCHES}; do cmp -s "${HERE}/${patch}.patch" "${SRC}/patches/${patch}.patch" || STALE=1; done
BASE=$(git -C "${SRC}" rev-parse "HEAD~${COMMITS}" 2> /dev/null || true)
SUBJECT=$(git -C "${SRC}" log --format=%s -1 2> /dev/null || true)
if [ "${BASE}" != "${HEAD_SHA}" ] || [ "${SUBJECT}" != "muse: patch set and release script" ] || [ "${STALE}" = 1 ]; then
  rm -rf "${SRC}"
  git clone -q --depth 1 --branch "${BRANCH}" "${UPSTREAM}" "${SRC}"
  cd "${SRC}"
  git checkout -q -b main
  for patch in ${PATCHES}; do
    git apply --check "${HERE}/${patch}.patch" || {
      echo "patch ${patch} does not apply to ${BRANCH} at ${SHORT}" >&2
      exit 1
    }
    git apply "${HERE}/${patch}.patch"
    git add -A
    git commit -q -m "muse: ${patch}"
  done
  mkdir -p patches
  for patch in ${PATCHES}; do cp "${HERE}/${patch}.patch" patches/; done
  cp "${HERE}/release.sh" "${HERE}/window-check.sh" "${HERE}/net-check.sh" "${HERE}/export-check.sh" "${HERE}/quit-app.sh" patches/
  git add patches
  git commit -q -m "muse: patch set and release script"
fi
cd "${SRC}"

QT_URL=$(sed -n "s/^wget .* -O Qt-.*7z '\(.*\)'$/\1/p" buildscripts/ci/macos/install_qt.sh)
if [ ! -d "${DEPS}/lib" ]; then
  mkdir -p "${DEPS}"
  curl -sSL https://raw.githubusercontent.com/cbjeukendrup/musescore_deps/main/musescore_deps_macos.tar.gz | tar xz -C "${DEPS}"
fi
if [ ! -d "${QT}/lib/cmake/Qt6" ]; then
  mkdir -p "${QT}"
  curl -sSL -o "${QT}/qt.7z" "${QT_URL}"
  SEVENZIP=$(command -v 7z || command -v 7zz) || {
    echo "no 7z or 7zz on PATH" >&2
    exit 1
  }
  (cd "${QT}" && "${SEVENZIP}" x -y qt.7z > /dev/null && rm qt.7z)
fi
export CMAKE_PREFIX_PATH="${QT}" PATH="${QT}/bin:${PATH}"
LEAN="-DMUE_BUILD_MACOS_INTEGRATION=OFF -DMUSE_MODULE_LANGUAGES=OFF -DMUSE_MODULE_MUSESAMPLER=OFF -DMUE_BUILD_BRAILLE_MODULE=OFF -DMUE_BUILD_BRAILLE_QML=OFF -DMUE_BUILD_MUSESOUNDS_MODULE=OFF -DMUE_BUILD_MUSESOUNDS_QML=OFF -DMUSE_MODULE_CLOUD=OFF -DMUSE_MODULE_CLOUD_MUSESCORECOM=OFF -DMUSE_MODULE_LEARN=OFF -DMUSE_MODULE_TOURS=OFF -DMUSE_MODULE_NETWORK=OFF -DMUSE_MODULE_UPDATE=OFF -DMUSE_MODULE_AUTOBOT=OFF -DMUSE_MODULE_VST=OFF -DMUSE_MODULE_AUDIOPLUGINS=OFF -DMUE_BUILD_IMPEXP_GUITARPRO_MODULE=OFF -DMUE_BUILD_IMPEXP_MEI_MODULE=OFF -DMUE_BUILD_IMPEXP_MNX_MODULE=OFF -DMUE_BUILD_IMPEXP_BB_MODULE=OFF -DMUE_BUILD_IMPEXP_BWW_MODULE=OFF -DMUE_BUILD_IMPEXP_CAPELLA_MODULE=OFF -DMUE_BUILD_IMPEXP_OVE_MODULE=OFF -DMUE_BUILD_IMPEXP_MUSEDATA_MODULE=OFF -DMUE_BUILD_IMPEXP_TABLEDIT_MODULE=OFF -DMUE_BUILD_IMPEXP_LYRICS_MODULE=OFF -DMUE_BUILD_IMPEXP_MIDI_MODULE=ON -DMUE_BUILD_IMPEXP_VIDEOEXPORT_MODULE=ON -DMUE_BUILD_IMPEXP_AUDIOEXPORT_MODULE=ON"
if [ -n "${MSCORE_APP_FROM:-}" ]; then
  # an app built elsewhere is packaged as it is; compiling here would delete it
  [ "${MSCORE_BUILD_ONLY:-}" = 1 ] && {
    echo "MSCORE_APP_FROM packages an app built elsewhere; it cannot be combined with MSCORE_BUILD_ONLY" >&2
    exit 1
  }
  MSCORE_PACKAGE_ONLY=1
  mkdir -p applebuild/mscore.app
  rsync -a --delete "${MSCORE_APP_FROM}/" applebuild/mscore.app/ < /dev/null
fi
if [ "${MSCORE_PACKAGE_ONLY:-}" != 1 ]; then
  # QML resolves imports only at launch, so a folder left out of the build is refused here, before the compile
  python3 "${HERE}/qml-imports.py" . > /dev/null
  # and an assignment to a positioner's own implicit size, which QML also refuses only at launch
  python3 "${HERE}/qml-readonly.py" . > /dev/null
  # packaging rewrites the bundle in place (it renames qml, prunes Qt, signs), so every install starts from none
  rm -rf applebuild/mscore.app
  MUSESCORE_CMAKE_ARGS="${LEAN}" CMAKE_OSX_ARCHITECTURES=arm64 MUSE_APP_BUILD_MODE=release MUSESCORE_INSTALL_DIR=../applebuild \
    MUSESCORE_MACOS_DEPS_PATH="${DEPS}" MUSESCORE_DOWNLOAD_SOUNDFONT=OFF MUSESCORE_MODULE_UPDATE=OFF \
    bash -e ./ninja_build.sh -t install < /dev/null
  # A module that is on with its own QML off builds cleanly and opens no window: refuse it here
  MISSING_QML=$(awk -F'[:=]' '/^MUE_BUILD_[A-Z_]+_MODULE:BOOL=ON$/ {sub(/_MODULE$/, "", $1); on[$1] = 1} /^MUE_BUILD_[A-Z_]+_QML:BOOL=OFF$/ {sub(/_QML$/, "", $1); off[$1] = 1} END {for (m in on) if (m in off) print m}' build.release/CMakeCache.txt)
  if [ -n "${MISSING_QML}" ]; then
    echo "modules on with their QML off: ${MISSING_QML}" >&2
    exit 1
  fi
  # the patched modules' unit tests, in a build folder beside the tree with the same options, refuse any failure the
  # untouched upstream base does not share
  # MSCORE_ITERATE=1 skips them for a build-only iteration on 1 change; a build that publishes always runs them
  if [ "${MSCORE_ITERATE:-}" = 1 ] && [ "${MSCORE_BUILD_ONLY:-}" != 1 ]; then
    echo "MSCORE_ITERATE needs MSCORE_BUILD_ONLY: a build that publishes runs every unit test" >&2
    exit 1
  fi
  if [ "${MSCORE_ITERATE:-}" != 1 ]; then
    TESTS_OUT=$(sh "${HERE}/tools/unit-tests.sh" "${PWD}" "${PWD}-tests" "${QT}" "${DEPS}" 2>&1) || {
      printf '%s\n' "${TESTS_OUT}" >&2
      exit 1
    }
  fi
fi
# a built app carries the release's own bundle identifier, and macOS hands a double-clicked score to any registered copy,
# so every copy this script leaves in the build tree is taken out of Launch Services
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
unregister() { "${LSREGISTER}" -u "$1" > /dev/null 2>&1 || true; }
trap 'unregister "${PWD}/applebuild/mscore.app"; unregister "${PWD}/applebuild/test/mscore.app"; rm -f "$0"' EXIT
[ -x applebuild/mscore.app/Contents/MacOS/mscore ] || {
  echo "build produced no app" >&2
  exit 1
}
[ "${MSCORE_BUILD_ONLY:-}" = 1 ] && {
  echo "built ${SRC}/applebuild/mscore.app"
  exit 0
}

: "${MSCORE_SECRETS:?set MSCORE_SECRETS to the folder holding the App Store Connect API key}"
IDENTITY=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)
[ -n "${IDENTITY}" ] || {
  echo "no Developer ID Application identity in the keychain" >&2
  exit 1
}
for name in asc-api.p8 asc-api-key-id.txt asc-api-issuer-id.txt; do
  [ -s "${MSCORE_SECRETS}/${name}" ] || {
    echo "missing ${MSCORE_SECRETS}/${name}" >&2
    exit 1
  }
done

BINARY=applebuild/mscore.app/Contents/MacOS/mscore
strip -S -x "${BINARY}"
for dir in "${QT}/lib" "${DEPS}/lib"; do
  otool -l "${BINARY}" | grep -q "path ${dir} " || install_name_tool -add_rpath "${dir}" "${BINARY}"
done
codesign --force --sign - "${BINARY}" 2> /dev/null

: "${MSCORE_CHECK_SCORE:?set MSCORE_CHECK_SCORE to a score the built app opens for the window check}"
# every check runs a copy under the test bundle identifier, whose settings are its own, never the owner's; with
# MSCORE_CHECK_HOST set, the checks run on that Mac over ssh, so they never take this Mac's screen, against
# MSCORE_CHECK_REMOTE_SCORE, its own copy of the check score, from its own clone of this repository at ~/muse/mslite
gates() { checks "$1" gates; }
features() { checks "$1" features; }
checks() {
  if [ -z "${MSCORE_CHECK_HOST:-}" ]; then
    sh "${HERE}/tools/app-checks.sh" "$1" "${MSCORE_CHECK_SCORE}" "$2"
    return
  fi
  : "${MSCORE_CHECK_REMOTE_SCORE:?set MSCORE_CHECK_REMOTE_SCORE to the path of the check score on ${MSCORE_CHECK_HOST}}"
  rsync -a --delete "$1/" "${MSCORE_CHECK_HOST}:mscore-check/mscore.app/"
  commit=$(git -C "${HERE}" rev-parse HEAD)
  printf '%s\n%s\n%s\n' "${commit}" "${MSCORE_CHECK_REMOTE_SCORE}" "$2" | ssh "${MSCORE_CHECK_HOST}" sh muse/mslite/tools/remote-checks.sh
}
# the unpackaged app loads Qt and the dependencies from this Mac's own folders, so another Mac can only check the packaged
# app; in that case the 4 gates run once, after packaging, beside the features
[ -n "${MSCORE_CHECK_HOST:-}" ] || gates applebuild/mscore.app

KEY_ID=$(cat "${MSCORE_SECRETS}/asc-api-key-id.txt")
ISSUER=$(cat "${MSCORE_SECRETS}/asc-api-issuer-id.txt")
SIGN_IDENTITY="${IDENTITY}" NOTARY_KEY="${MSCORE_SECRETS}/asc-api.p8" \
  NOTARY_KEY_ID="${KEY_ID}" NOTARY_ISSUER="${ISSUER}" \
  bash buildscripts/packaging/macOS/package.sh --app-name "MuseScoreLite" --vol-name "MuseScoreLite-${SHORT}" --sign < /dev/null
DMG="applebuild/MuseScoreLite-${SHORT}.dmg"
[ -s "${DMG}" ] || {
  echo "packaging produced no disk image" >&2
  exit 1
}
xcrun stapler validate "applebuild/mscore.app"
gates applebuild/mscore.app
# every feature the owner uses, driven on the packaged app before anything is published, since packaging removes Qt
# parts and the 4 gates above judge none of the features
features applebuild/mscore.app
[ "${MSCORE_SKIP_PUBLISH:-}" = 1 ] && {
  echo "packaged ${SRC}/${DMG}"
  exit 0
}

NOTES="Upstream ${BRANCH} at musescore/MuseScore@${HEAD_SHA} with: --serve (1 conversion job per stdin line, stays running, no Dock icon); a lean, fully offline reading and playing app: the sheet alone on a filled screen under a merged title bar, the open score's name as the bold app menu title, no home page or tabs, a standard Window menu, no internet access at all, no welcome, tours, account, cloud, online publishing, update check, online help, Muse Sounds, translations or bundled soundfont (add your own .sf2/.sf3); live MIDI input sounding during playback; the keyboard panel (61 keys) lighting each sounding key in its layer's colour (your live notes, then staff 1, staff 2 and on, then chords); the last sound you picked per staff position, metronome and chord track remembered for every new score, a score's own saved sounds winning, and no default sound ever; a flat SoundFont picker and a mixer with only sound, volume, mute and solo; every other panel floating and fitted to its content. English only, High-contrast Black theme, data in ~/mslite. Apple Silicon only, signed and notarized."
git push -q --force "https://github.com/${FORK}.git" HEAD:refs/heads/main "HEAD:refs/tags/${SHORT}"
if gh release view "${SHORT}" --repo "${FORK}" > /dev/null 2>&1; then
  gh release upload "${SHORT}" "${DMG}" --repo "${FORK}" --clobber
  gh release edit "${SHORT}" --repo "${FORK}" --title "${SHORT}" --notes "${NOTES}" > /dev/null
else
  gh release create "${SHORT}" "${DMG}" --repo "${FORK}" --target main --latest --title "${SHORT}" --notes "${NOTES}"
fi
# The newest build is the only one kept: every other release and its tag goes
for old in $(gh release list --repo "${FORK}" --json tagName --jq ".[].tagName | select(. != \"${SHORT}\")"); do
  gh release delete "${old}" --repo "${FORK}" --cleanup-tag --yes
done
echo "released ${SHORT}"
