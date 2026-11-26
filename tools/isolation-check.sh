#!/bin/sh
# Prove a test launch cannot reach a running copy of the app. Start a listening copy on the machine's normal temp folder,
# then require that a launch sharing that temp folder reaches it (the control) and that fresh-launch.sh, which gives its
# launch a temp folder of its own, does not.
# usage: isolation-check.sh <mscore binary> <score>
# Needs no other copy of the app running, so the listener is the only one.
set -eu
[ "$#" -eq 2 ] || {
  echo "usage: isolation-check.sh <mscore binary> <score>" >&2
  exit 2
}
BINARY=$1
SCORE=$2
script_dir=$(dirname -- "$0")
HERE=$(CDPATH='' cd -- "${script_dir}/.." && pwd)
sh "${HERE}/tools/test-app.sh" "${BINARY}" "${SCORE}"
LISTENER_HOME=$(mktemp -d)
SHARED_HOME=$(mktemp -d)
HOME="${LISTENER_HOME}" "${BINARY}" "${SCORE}" < /dev/null > /dev/null 2>&1 &
LISTENER=$!
now=$(date +%s)
deadline=$((now + 60))
log=""
while [ -z "${log}" ]; do
  now=$(date +%s)
  [ "${now}" -le "${deadline}" ] || {
    echo "the listening copy wrote no log within 60 s" >&2
    kill "${LISTENER}" 2> /dev/null || true
    exit 1
  }
  log=$(/usr/bin/find "${LISTENER_HOME}/mslite/logs" -name '*.log' 2> /dev/null | head -1)
  sleep 1
done
sleep 10
messages() { grep -c "MultiProcessProvider::onMsg" "${log}" || true; }
start=$(messages)
HOME="${SHARED_HOME}" "${BINARY}" "${SCORE}" < /dev/null > /dev/null 2>&1 &
SHARED=$!
sleep 20
sh "${HERE}/quit-app.sh" "${SHARED}" > /dev/null 2>&1 || true
sleep 2
shared=$(messages)
sh "${HERE}/tools/fresh-launch.sh" "${BINARY}" "${SCORE}" > /dev/null 2>&1 || true
sleep 2
isolated=$(messages)
sh "${HERE}/quit-app.sh" "${LISTENER}" > /dev/null 2>&1 || true
rm -rf "${LISTENER_HOME}" "${SHARED_HOME}"
if [ "${shared}" -le "${start}" ]; then
  echo "the control failed: a launch sharing the temp folder sent the listener nothing (${start} then ${shared})" >&2
  exit 1
fi
if [ "${isolated}" -ne "${shared}" ]; then
  echo "an isolated launch reached the listener: ${shared} messages before it, ${isolated} after" >&2
  exit 1
fi
echo "ok (a shared launch sent $((shared - start)) messages, the isolated launch none)"
