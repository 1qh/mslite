#!/bin/sh
# Build upstream MuseScore's newest release with every patch, for Apple Silicon, sign, notarize, and publish it.
# Needs the Developer ID Application identity in the keychain, and MSCORE_SECRETS naming the folder that holds
# asc-api.p8, asc-api-key-id.txt and asc-api-issuer-id.txt (an App Store Connect API key, for notarization).
# MSCORE_BUILD_ONLY=1 stops after the compile (the compile Mac); MSCORE_PACKAGE_ONLY=1 skips it and, with
# MSCORE_APP_FROM naming an rsync source such as host:path/mscore.app, packages the app built there.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
FORK=${MSCORE_FORK:-1qh/MuseScore}
SRC=${MSCORE_RELEASE_SRC:-${HERE}/../mscore-release}
DEPS=${MSCORE_DEPS:-${HERE}/../mscore-deps}
QT=${MSCORE_QT:-${HERE}/../mscore-qt}
PATCHES="serve piano-playback packaging flat-picker debloat"
TAG=${MSCORE_TAG:-$(gh api repos/musescore/MuseScore/releases/latest --jq .tag_name)}
COMMITS=$(($(echo "${PATCHES}" | wc -w) + 1))
STALE=0
for patch in ${PATCHES}; do cmp -s "${HERE}/${patch}.patch" "${SRC}/patches/${patch}.patch" || STALE=1; done
DESCRIBED=$(git -C "${SRC}" describe --tags --exact-match "HEAD~${COMMITS}" 2> /dev/null || true)
SUBJECT=$(git -C "${SRC}" log --format=%s -1 2> /dev/null || true)
if [ "${DESCRIBED}" != "${TAG}" ] || [ "${SUBJECT}" != "muse: patch set and release script" ] || [ "${STALE}" = 1 ]; then
  rm -rf "${SRC}"
  git clone -q --depth 1 --branch "${TAG}" https://github.com/musescore/MuseScore.git "${SRC}"
  cd "${SRC}"
  git checkout -q -b "release/${TAG}"
  for patch in ${PATCHES}; do
    git apply --check "${HERE}/${patch}.patch" || {
      echo "patch ${patch} does not apply to ${TAG}" >&2
      exit 1
    }
    git apply "${HERE}/${patch}.patch"
    git add -A
    git -c user.name=muse -c user.email=muse@users.noreply.github.com commit -q -m "muse: ${patch}"
  done
  mkdir -p patches
  for patch in ${PATCHES}; do cp "${HERE}/${patch}.patch" patches/; done
  cp "${HERE}/release.sh" "${HERE}/window-check.sh" "${HERE}/net-check.sh" "${HERE}/export-check.sh" "${HERE}/quit-app.sh" patches/
  git add patches
  git -c user.name=muse -c user.email=muse@users.noreply.github.com commit -q -m "muse: patch set and release script"
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
LEAN="-DMUE_BUILD_MACOS_INTEGRATION=OFF -DMUSE_MODULE_LANGUAGES=OFF -DMUSE_MODULE_MUSESAMPLER=OFF -DMUE_BUILD_BRAILLE_MODULE=ON -DMUE_BUILD_BRAILLE_QML=ON -DMUSE_MODULE_UPDATE=OFF -DMUSE_MODULE_AUTOBOT=OFF -DMUSE_MODULE_VST=OFF -DMUSE_MODULE_AUDIOPLUGINS=OFF -DMUE_BUILD_IMPEXP_GUITARPRO_MODULE=OFF -DMUE_BUILD_IMPEXP_MEI_MODULE=OFF -DMUE_BUILD_IMPEXP_MNX_MODULE=OFF -DMUE_BUILD_IMPEXP_BB_MODULE=OFF -DMUE_BUILD_IMPEXP_BWW_MODULE=OFF -DMUE_BUILD_IMPEXP_CAPELLA_MODULE=OFF -DMUE_BUILD_IMPEXP_OVE_MODULE=OFF -DMUE_BUILD_IMPEXP_MUSEDATA_MODULE=OFF -DMUE_BUILD_IMPEXP_TABLEDIT_MODULE=OFF -DMUE_BUILD_IMPEXP_LYRICS_MODULE=OFF -DMUE_BUILD_IMPEXP_MIDI_MODULE=ON -DMUE_BUILD_IMPEXP_VIDEOEXPORT_MODULE=OFF -DMUE_BUILD_IMPEXP_AUDIOEXPORT_MODULE=OFF"
if [ -n "${MSCORE_APP_FROM:-}" ]; then
  mkdir -p applebuild/mscore.app
  rsync -a --delete "${MSCORE_APP_FROM}/" applebuild/mscore.app/ < /dev/null
fi
if [ "${MSCORE_PACKAGE_ONLY:-}" != 1 ]; then
  MUSESCORE_CMAKE_ARGS="${LEAN}" CMAKE_OSX_ARCHITECTURES=arm64 MUSE_APP_BUILD_MODE=release MUSESCORE_INSTALL_DIR=../applebuild \
    MUSESCORE_MACOS_DEPS_PATH="${DEPS}" MUSESCORE_DOWNLOAD_SOUNDFONT=OFF MUSESCORE_MODULE_UPDATE=OFF \
    bash -e ./ninja_build.sh -t install < /dev/null
  # A module that is on with its own QML off builds cleanly and opens no window: refuse it here
  MISSING_QML=$(awk -F'[:=]' '/^MUE_BUILD_[A-Z_]+_MODULE:BOOL=ON$/ {sub(/_MODULE$/, "", $1); on[$1] = 1} /^MUE_BUILD_[A-Z_]+_QML:BOOL=OFF$/ {sub(/_QML$/, "", $1); off[$1] = 1} END {for (m in on) if (m in off) print m}' build.release/CMakeCache.txt)
  if [ -n "${MISSING_QML}" ]; then
    echo "modules on with their QML off: ${MISSING_QML}" >&2
    exit 1
  fi
fi
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
sh "${HERE}/window-check.sh" "${BINARY}" "${MSCORE_CHECK_SCORE}"
sh "${HERE}/net-check.sh" "${BINARY}" "${MSCORE_CHECK_SCORE}"
sh "${HERE}/export-check.sh" "${BINARY}" "${MSCORE_CHECK_SCORE}"

KEY_ID=$(cat "${MSCORE_SECRETS}/asc-api-key-id.txt")
ISSUER=$(cat "${MSCORE_SECRETS}/asc-api-issuer-id.txt")
VERSION=${TAG#v}
SIGN_IDENTITY="${IDENTITY}" NOTARY_KEY="${MSCORE_SECRETS}/asc-api.p8" \
  NOTARY_KEY_ID="${KEY_ID}" NOTARY_ISSUER="${ISSUER}" \
  bash buildscripts/packaging/macOS/package.sh --app-name "MuseScoreLite" --vol-name "MuseScoreLite-${VERSION}" --sign < /dev/null
DMG="applebuild/MuseScoreLite-${VERSION}.dmg"
[ -s "${DMG}" ] || {
  echo "packaging produced no disk image" >&2
  exit 1
}
xcrun stapler validate "applebuild/mscore.app"
sh "${HERE}/window-check.sh" "${PWD}/applebuild/mscore.app/Contents/MacOS/mscore" "${MSCORE_CHECK_SCORE}"
sh "${HERE}/net-check.sh" "${PWD}/applebuild/mscore.app/Contents/MacOS/mscore" "${MSCORE_CHECK_SCORE}"
sh "${HERE}/export-check.sh" "${PWD}/applebuild/mscore.app/Contents/MacOS/mscore" "${MSCORE_CHECK_SCORE}"
[ "${MSCORE_SKIP_PUBLISH:-}" = 1 ] && {
  echo "packaged ${SRC}/${DMG}"
  exit 0
}

git push -q --force "https://github.com/${FORK}.git" "release/${TAG}"
NOTES="Upstream ${TAG} with: --serve (1 conversion job per stdin line, stays running, no Dock icon), the keyboard panel lighting the notes sounding during playback (upstream PR 34351) and shown only while the score plays, the flat SoundFont picker (every preset in 1 menu under a header per font), and a lean, fully offline reading app: the sheet alone on a filled screen under a merged title bar, no home page or tabs, a standard Window menu, no internet access at all, no welcome, tours, account, cloud, online publishing, update check, online help, Muse Sounds, translations or bundled soundfont (add your own .sf2/.sf3), English only, High-contrast Black theme, data in ~/mslite. Apple Silicon only, signed and notarized."
if gh release view "${TAG}-muse" --repo "${FORK}" >/dev/null 2>&1; then
  gh release upload "${TAG}-muse" "${DMG}" --repo "${FORK}" --clobber
  gh release edit "${TAG}-muse" --repo "${FORK}" --title "MuseScoreLite ${VERSION}" --notes "${NOTES}" >/dev/null
else
  gh release create "${TAG}-muse" "${DMG}" --repo "${FORK}" --target "release/${TAG}" --title "MuseScoreLite ${VERSION}" --notes "${NOTES}"
fi
echo "released ${TAG}-muse"
