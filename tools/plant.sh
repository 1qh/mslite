#!/bin/sh
# Mutation control for 1 unit test target: plant a defect by replacing an exact line of a source file, rebuild and run
# the target, then restore the file from a copy and confirm it is byte-identical. The control passes when the planted
# run fails.
# usage: plant.sh <source tree> <test build folder> <target> <file under the tree> <exact line> <replacement line>
set -eu
[ "$#" -eq 6 ] || {
  echo "usage: plant.sh <source tree> <test build folder> <target> <file> <exact line> <replacement line>" >&2
  exit 2
}
SRC=$1
OUT=$2
TARGET=$3
FILE="${SRC}/$4"
LINE=$5
WITH=$6
SAVED=$(mktemp)
cp "${FILE}" "${SAVED}"
found=$(grep -cxF -- "${LINE}" "${FILE}" || true)
[ "${found}" -eq 1 ] || {
  echo "the line to plant over appears ${found} times in $4, not once" >&2
  exit 1
}
python3 -c 'import sys; p, o, n = sys.argv[1:4]; s = open(p).read(); open(p, "w").write(s.replace(o + "\n", n + "\n", 1))' \
  "${FILE}" "${LINE}" "${WITH}"
grep -qxF -- "${WITH}" "${FILE}" || {
  cp "${SAVED}" "${FILE}"
  echo "the plant did not apply" >&2
  exit 1
}
verdict="the planted defect PASSED: the test cannot see it"
if ninja -C "${OUT}" "${TARGET}" > "${OUT}.plant.build.log" 2>&1 < /dev/null; then
  binary=$(find "${OUT}" -type f -perm -u+x -name "${TARGET}" | head -1)
  if ! (cd "$(dirname "${binary}")" && "${binary}" > "${OUT}.plant.run.log" 2>&1 < /dev/null); then
    verdict="ok (planted defect failed: $(grep -m3 '^\[  FAILED  \]' "${OUT}.plant.run.log" | tr '\n' ' '))"
  fi
else
  verdict="the planted defect does not compile, so it proves nothing about the test"
fi
cp "${SAVED}" "${FILE}"
# cp clones on APFS and keeps the saved copy's old time, older than the planted build, so the rebuild below would keep the
# planted binary; touching makes the restore newer than it
touch "${FILE}"
cmp -s "${SAVED}" "${FILE}" || {
  echo "the file was not restored" >&2
  exit 1
}
ninja -C "${OUT}" "${TARGET}" > /dev/null 2>&1 < /dev/null || true
echo "${verdict}"
case "${verdict}" in ok*) exit 0 ;; *) exit 1 ;; esac
