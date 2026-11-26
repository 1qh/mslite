#!/bin/sh
# Release MuseScoreLite when the head of upstream's current release branch moves, run once a day by schedule.sh.
# Publishes nothing on any failure, and raises a macOS notification naming the log instead.
# Needs MSCORE_SECRETS and MSCORE_CHECK_SCORE, as release.sh does.
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
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"
LOG="${HOME}/Library/Logs/mslite-release/release.log"
mkdir -p "$(dirname "${LOG}")"
LATEST=$(gh api repos/musescore/MuseScore/releases/latest --jq .tag_name) || exit 1
BRANCH=${MSCORE_BRANCH:-$(echo "${LATEST#v}" | cut -d. -f1-2)}
HEAD_SHA=$(git ls-remote https://github.com/musescore/MuseScore.git "refs/heads/${BRANCH}" | cut -f1)
SHORT=$(echo "${HEAD_SHA}" | cut -c1-8)
if gh release view "${SHORT}" --repo "${MSCORE_FORK:-1qh/MuseScore}" > /dev/null 2>&1; then
  echo ok
  exit 0
fi
if sh "${HERE}/release.sh" > "${LOG}" 2>&1 < /dev/null; then
  osascript -e "display notification \"Released ${BRANCH} at ${HEAD_SHA}\" with title \"MuseScoreLite\"" > /dev/null 2>&1
  echo ok
  exit 0
fi
osascript -e "display notification \"Release failed, see ${LOG}\" with title \"MuseScoreLite\"" > /dev/null 2>&1
tail -20 "${LOG}" >&2
exit 1
