#!/bin/sh
# Run on the checking Mac over ssh: bring its clone of this repository to the commit the releasing Mac runs, refuse any
# other commit, then run the app checks on the app copied to ~/mscore-check.
# usage: printf '%s\n%s\n%s\n' <commit> <score> gates|features | remote-checks.sh
set -eu
IFS= read -r commit
IFS= read -r score
IFS= read -r kind
exec < /dev/null
export PATH="/opt/homebrew/bin:${PATH}"
REPO="${HOME}/muse/mslite"
git -C "${REPO}" pull -q --ff-only
head=$(git -C "${REPO}" rev-parse HEAD)
[ "${head}" = "${commit}" ] || {
  echo "the checking clone is at ${head}, not the released commit ${commit}" >&2
  exit 1
}
sh "${REPO}/tools/app-checks.sh" "${HOME}/mscore-check/mscore.app" "${score}" "${kind}"
