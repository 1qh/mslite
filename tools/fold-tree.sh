#!/bin/sh
# Fold a build tree's uncommitted source changes into its debloat commit and refresh its patch-set commit from mslite,
# so release.sh finds the tree current and compiles incrementally instead of cloning afresh.
# usage: fold-tree.sh <build tree> <mslite checkout>
set -eu
SRC=$1
HERE=$2
cd "${SRC}"
[ "$(git log --format=%s -1)" = "muse: patch set and release script" ] || {
  echo "the top commit of ${SRC} is not the patch-set commit" >&2
  exit 1
}
[ "$(git log --format=%s -1 HEAD~1)" = "muse: debloat" ] || {
  echo "the commit under the patch set in ${SRC} is not the debloat commit" >&2
  exit 1
}
git reset -q --soft HEAD~1
git reset -q -- patches
git add -A -- src
git commit -q --amend --no-edit
for patch in serve piano-playback packaging flat-picker debloat; do cp "${HERE}/${patch}.patch" patches/; done
cp "${HERE}/release.sh" "${HERE}/window-check.sh" "${HERE}/net-check.sh" "${HERE}/export-check.sh" "${HERE}/quit-app.sh" patches/
git add patches
git commit -q -m "muse: patch set and release script"
for patch in serve piano-playback packaging flat-picker debloat; do
  cmp -s "${HERE}/${patch}.patch" "patches/${patch}.patch" || {
    echo "patches/${patch}.patch differs from mslite after folding" >&2
    exit 1
  }
done
[ -z "$(git status --porcelain -- src patches)" ] || {
  echo "source changes remain uncommitted in ${SRC}" >&2
  exit 1
}
echo ok
