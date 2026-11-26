"""Prove the running app applies the metronome sound a score saved.

Prove the running app applies the metronome sound a score saved: write a pick naming a sound no soundfont has into a
copy of a score, open the copy on an empty data folder, and find the audio engine's `Not found: <id>` for that pick.

usage: python3 -m tools.metronome_pick (from mslite) <mscore binary> <score>
Prints `ok` when the pick is applied from the score and a copy without the pick names nothing; exits non-zero otherwise.
"""

import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import time
import uuid
import zipfile

HERE = pathlib.Path(__file__).resolve().parent.parent
ARGC = 3
LOG_WAIT_SECONDS = 60
SETTLE_SECONDS = 15
METRONOME_PART = "999"
METRONOME_INSTRUMENT = "metronome"


def with_pick(score: pathlib.Path, out: pathlib.Path, resource: str | None) -> None:
    """Copy a score, adding a metronome track to its audio settings when a resource is named.

    Args:
        score: The score to copy.
        out: Where the copy goes.
        resource: The sound id the metronome is set to, or none to leave the score's settings untouched.

    Raises:
        TypeError: when the score's audio settings hold no object, or their tracks no list.

    """
    with zipfile.ZipFile(score) as source, zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as target:
        settings: dict[str, object] = {"tracks": []}
        for item in source.infolist():
            if item.filename == "audiosettings.json":
                loaded = json.loads(source.read(item))
                if not isinstance(loaded, dict):
                    msg = f"{score}: audiosettings.json holds no object"
                    raise TypeError(msg)
                settings = {str(key): value for key, value in loaded.items()}
                continue
            target.writestr(item, source.read(item))
        if resource is not None:
            saved = settings.get("tracks", [])
            if not isinstance(saved, list):
                msg = f"{score}: audiosettings.json tracks are no list"
                raise TypeError(msg)
            tracks = [track for track in saved if not isinstance(track, dict) or track.get("partId") != METRONOME_PART]
            tracks.append({
                "partId": METRONOME_PART,
                "instrumentId": METRONOME_INSTRUMENT,
                "in": {"resourceMeta": {"id": resource, "type": "fluid_soundfont", "vendor": "Fluid", "attributes": {}}},
                "out": {},
            })
            settings["tracks"] = tracks
        target.writestr("audiosettings.json", json.dumps(settings))


def launch_log(binary: pathlib.Path, score: pathlib.Path) -> tuple[str, bool]:
    """Open a score in the app on an empty data folder, quit it, and return its log.

    Args:
        binary: The app's executable.
        score: The score to open.

    Returns:
        The text of the log the launch wrote, and whether the app quit cleanly, which a modal dialog prevents.

    Raises:
        RuntimeError: when the app writes no log.

    """
    home = pathlib.Path(tempfile.mkdtemp())
    try:
        env = {**os.environ, "HOME": str(home), "TMPDIR": str(home)}
        process = subprocess.Popen(
            [str(binary), str(score)],
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        deadline = time.monotonic() + LOG_WAIT_SECONDS
        logs: list[pathlib.Path] = []
        while not logs and time.monotonic() < deadline and process.poll() is None:
            logs = sorted((home / "mslite" / "logs").glob("*.log"))
            time.sleep(1)
        time.sleep(SETTLE_SECONDS)
        quit_app = shutil.which("sh") or "sh"
        quit_status = subprocess.run(
            [quit_app, str(HERE / "quit-app.sh"), str(process.pid)],
            stdin=subprocess.DEVNULL,
            check=False,
        ).returncode
        process.wait()
        if not logs:
            msg = f"the app wrote no log within {LOG_WAIT_SECONDS} s"
            raise RuntimeError(msg)
        return logs[0].read_text(encoding="utf-8", errors="replace"), quit_status == 0
    finally:
        shutil.rmtree(home, ignore_errors=True)


def main() -> int:
    """Run the probe and its control.

    Returns:
        0 when the pick is applied and the control names nothing, 1 otherwise, 2 on bad arguments.

    """
    if len(sys.argv) != ARGC:
        sys.stderr.write("usage: metronome_pick.py <mscore binary> <score>\n")
        return 2
    binary, score = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    guard = subprocess.run(
        [shutil.which("sh") or "sh", str(HERE / "tools" / "test-app.sh"), str(binary), str(score)],
        stdin=subprocess.DEVNULL,
        check=False,
    )
    if guard.returncode:
        return guard.returncode
    pick = f"mslite-probe-{uuid.uuid4().hex}"
    work = pathlib.Path(tempfile.mkdtemp())
    try:
        picked, plain = work / "picked.mscz", work / "plain.mscz"
        with_pick(score, picked, pick)
        with_pick(score, plain, None)
        picked_log, picked_clean = launch_log(binary, picked)
        plain_log, plain_clean = launch_log(binary, plain)
        applied = f"Not found: {pick}" in picked_log
        control = "mslite-probe-" in plain_log
        sys.stdout.write(
            f"picked: applied={applied} quit_clean={picked_clean}; plain: named={control} quit_clean={plain_clean}\n",
        )
        for line in picked_log.splitlines():
            if pick in line or "ERROR" in line:
                sys.stdout.write(f"  {line[:200]}\n")
    finally:
        shutil.rmtree(work, ignore_errors=True)
    if not applied:
        sys.stderr.write(f"the app never asked the audio engine for the score's metronome pick {pick}\n")
        return 1
    if control:
        sys.stderr.write("a score without a pick still asked for one: the probe cannot tell them apart\n")
        return 1
    sys.stdout.write("ok (the score's metronome pick reached the audio engine; a score without one named none)\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
