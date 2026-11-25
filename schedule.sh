#!/bin/sh
# Install the daily MuseScoreLite release check as a LaunchAgent, idempotently.
# usage: schedule.sh <secrets folder> <score the checks open>
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
SECRETS=${1:?usage: schedule.sh <secrets folder> <score>}
SCORE=${2:?usage: schedule.sh <secrets folder> <score>}
LABEL=org.mslite.auto-release
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
mkdir -p "${HOME}/Library/LaunchAgents" "${HOME}/Library/Logs/mslite-release"
cat > "${PLIST}.new" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${LABEL}</string>
  <key>ProgramArguments</key><array><string>/bin/sh</string><string>${HERE}/auto-release.sh</string></array>
  <key>EnvironmentVariables</key><dict>
    <key>MSCORE_SECRETS</key><string>${SECRETS}</string>
    <key>MSCORE_CHECK_SCORE</key><string>${SCORE}</string>
  </dict>
  <key>StartCalendarInterval</key><dict><key>Hour</key><integer>4</integer><key>Minute</key><integer>0</integer></dict>
  <key>StandardOutPath</key><string>${HOME}/Library/Logs/mslite-release/auto-release.out</string>
  <key>StandardErrorPath</key><string>${HOME}/Library/Logs/mslite-release/auto-release.out</string>
</dict>
</plist>
EOF
USER_ID=$(id -u)
plutil -lint "${PLIST}.new" > /dev/null
mv "${PLIST}.new" "${PLIST}"
launchctl bootout "gui/${USER_ID}/${LABEL}" 2> /dev/null || true
launchctl bootstrap "gui/${USER_ID}" "${PLIST}"
echo ok
