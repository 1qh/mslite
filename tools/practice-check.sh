#!/bin/sh
# Prove the practice video: a test copy exports a score with `--view-mode practice` as 3840x2160 HEVC tagged hvc1 with AAC
# sound, the count-in clicking from the start and the song sounding after it. The test copy's own settings domain gets 1
# remembered pick per slot, the metronome's included, since the app plays no default sound.
# usage: practice-check.sh <test copy's mscore binary> <score> <folder>
set -eu
[ "$#" -eq 3 ] || {
  echo "usage: practice-check.sh <test copy's mscore binary> <score> <folder>" >&2
  exit 2
}
BINARY=$1
SCORE=$2
OUT=$3
export PATH="/opt/homebrew/bin:${PATH}"
script_dir=$(dirname -- "$0")
HERE=$(CDPATH='' cd -- "${script_dir}/.." && pwd)
sh "${HERE}/tools/test-app.sh" "${BINARY}" "${SCORE}"
mkdir -p "${OUT}"
FRESH=$(mktemp -d)
trap 'rm -rf "${FRESH}"' EXIT
mkdir -p "${FRESH}/mslite"
cp -R "${HOME}/mslite/SoundFonts" "${FRESH}/mslite/"
pick() {
  printf '{"resourceMeta":{"attributes":{"playbackSetupData":"last.last.last","presetBank":"%s","presetName":"%s","presetProgram":"%s","soundFontName":"%s"},"hasNativeEditorSupport":false,"id":"%s\\\\%s\\\\%s","type":"fluid_soundfont","vendor":"Fluid"},"unitConfiguration":{}}' "$2" "$1" "$3" "$4" "$4" "$2" "$3"
}
chords=$(pick DynamicFullPad 22 8 PianoLayer)
metronome=$(pick WoodblockRound 21 52 Percussion)
staff=$(pick OrchestraRound 22 28 PianoLayer)
picks="{\"chords\":${chords},\"metronome\":${metronome},\"position/1\":${staff},\"position/2\":${staff}}"
defaults write org.musescore.MuseScoreLite.test playback.mixer.rememberedTrackInputs -string "${picks}"
VIDEO="${OUT}/practice.mp4"
HOME="${FRESH}" TMPDIR="${FRESH}" "${BINARY}" --view-mode practice -o "${VIDEO}" "${SCORE}" < /dev/null > "${OUT}/app.log" 2>&1 || {
  echo "the practice export failed; its log: ${OUT}/app.log" >&2
  exit 1
}
ffprobe -v error -show_entries stream=codec_name,codec_tag_string,width,height -of csv=p=0 "${VIDEO}" > "${OUT}/streams.txt"
streams=$(tr '\n' ' ' < "${OUT}/streams.txt")
case "${streams}" in
  *"hevc,hvc1,3840,2160"*"aac,mp4a"*) ;;
  *)
    echo "the practice video is not 3840x2160 HEVC hvc1 with AAC: ${streams}" >&2
    exit 1
    ;;
esac
ffmpeg -hide_banner -ss 20 -t 10 -i "${VIDEO}" -vn -af volumedetect -f null - > "${OUT}/volume.txt" 2>&1
song=$(sed -n 's/.*mean_volume: \([-0-9.]*\) dB.*/\1/p' "${OUT}/volume.txt")
awk -v v="${song}" 'BEGIN { exit !(v != "" && v > -60) }' || {
  echo "the practice video is silent after the count-in (${song} dB)" >&2
  exit 1
}
ffmpeg -v error -t 3 -i "${VIDEO}" -vn -ac 1 -ar 8000 -f s16le "${OUT}/count-in.raw"
od -An -v -td2 -w2 "${OUT}/count-in.raw" > "${OUT}/count-in.txt"
clicks=$(awk '{ v = $1 < 0 ? -$1 : $1; w = int((NR - 1) / 400); if (v > m[w]) m[w] = v } END { for (i in m) if (m[i] > 2000) n++; print n + 0 }' "${OUT}/count-in.txt")
[ "${clicks}" -ge 2 ] || {
  echo "the count-in has no clicks: ${clicks} loud 50 ms windows in its first 3 s" >&2
  exit 1
}
echo "ok (practice video 3840x2160 HEVC with sound at ${song} dB; ${clicks} click windows in the count-in)"
