#!/bin/sh
# Build and run the unit tests of the modules the patches change, in a build folder of their own beside the release
# build, with the release's own module options, so the tests judge the code that ships.
# usage: unit-tests.sh <source tree> <test build folder> <Qt folder> <deps folder>
# UNIT_TEST_TARGETS names other test targets than the default set.
# Prints 1 line per test binary with its verdict and exits non-zero when any fails to build or run.
set -eu
[ "$#" -eq 4 ] || {
  echo "usage: unit-tests.sh <source tree> <test build folder> <Qt folder> <deps folder>" >&2
  exit 2
}
SRC=$1
OUT=$2
QT=$3
DEPS=$4
HERE=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
LEAN=$(sed -n 's/^LEAN="\(.*\)"$/\1/p' "${HERE}/release.sh")
[ -n "${LEAN}" ] || {
  echo "no LEAN options found in release.sh" >&2
  exit 1
}
TARGETS=${UNIT_TEST_TARGETS:-playback_test notationscene_qml_tests notation_tests engraving_tests project_test project_qml_tests}
export CMAKE_PREFIX_PATH="${QT}" PATH="${QT}/bin:${PATH}"
# LEAN is a list of options: xargs splits it into cmake's arguments
printf '%s\n' "${LEAN}" | xargs cmake -S "${SRC}" -B "${OUT}" -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DMUE_COMPILE_MACOS_PRECOMPILED_DEPS_PATH="${DEPS}" -DMUE_DOWNLOAD_SOUNDFONT=OFF \
  -DMUSE_ENABLE_UNIT_TESTS=ON -DMUE_BUILD_NOTATION_TESTS=ON > "${OUT}.configure.log" 2>&1 || {
  tail -20 "${OUT}.configure.log" >&2
  exit 1
}
status=0
for target in ${TARGETS}; do
  if ninja -C "${OUT}" "${target}" > "${OUT}.${target}.build.log" 2>&1 < /dev/null; then
    binary=$(find "${OUT}" -type f -perm -u+x -name "${target}" | head -1)
    if [ -z "${binary}" ]; then
      echo "${target}: built, binary not found"
      status=1
    elif (cd "$(dirname "${binary}")" && "${binary}" > "${OUT}.${target}.run.log" 2>&1 < /dev/null); then
      echo "${target}: $(grep -E '^\[  PASSED  \]' "${OUT}.${target}.run.log" | tail -1)"
    else
      echo "${target}: FAILED: $(grep -E '^\[  FAILED  \]' "${OUT}.${target}.run.log" | head -5 | tr '\n' ' ')"
      status=1
    fi
  else
    echo "${target}: does not build: $(grep -m3 ' error: ' "${OUT}.${target}.build.log" | tr '\n' ' ')"
    status=1
  fi
done
exit "${status}"
