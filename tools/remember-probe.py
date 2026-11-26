"""Prove the running app gives a remembered sound to a score that saves none: write a remembered pick for staff
position 1, naming a sound no soundfont has, into a test copy's settings, open a score whose audio settings carry no
pick, and find the audio engine's `Not found: <id>` for it; a launch with no remembered pick must name none.

usage: python3 remember-probe.py <test copy's mscore binary> <score>
"""

import importlib.util
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile
import uuid
import zipfile

HERE = pathlib.Path(__file__).resolve().parent.parent
ARGC = 3
TEST_ID = "org.musescore.MuseScoreLite.test"
SLOTS_KEY = "playback.mixer.rememberedTrackInputs"
PROBE_PREFIX = "mslite-remember-"


def sibling(name: str) -> object:
    """Load a sibling tool as a module.

    Args:
        name: The tool's file name.

    Returns:
        The loaded module.

    Raises:
        ImportError: when the tool cannot be loaded.

    """
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), HERE / "tools" / name)
    if spec is None or spec.loader is None:
        raise ImportError(name)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def without_audio_settings(score: pathlib.Path, out: pathlib.Path) -> None:
    """Copy a score without its saved audio settings, so no track carries a pick of its own.

    Args:
        score: The score to copy.
        out: Where the copy goes.

    """
    with zipfile.ZipFile(score) as source, zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as target:
        for item in source.infolist():
            if item.filename != "audiosettings.json":
                target.writestr(item, source.read(item))


def set_slots(slots: dict[str, object] | None) -> None:
    """Write the remembered picks into the test copy's settings, or clear them.

    Args:
        slots: Slot name to input params, or none to remove the setting.

    """
    defaults = shutil.which("defaults") or "/usr/bin/defaults"
    subprocess.run([defaults, "delete", TEST_ID], stdin=subprocess.DEVNULL, capture_output=True, check=False)
    if slots is not None:
        subprocess.run([defaults, "write", TEST_ID, SLOTS_KEY, "-string", json.dumps(slots)],
                       stdin=subprocess.DEVNULL, check=True)


def main() -> int:
    """Run the probe and its control.

    Returns:
        0 when the remembered pick reaches the engine and the control names none, 1 otherwise, 2 on bad arguments.

    """
    if len(sys.argv) != ARGC:
        sys.stderr.write("usage: remember-probe.py <test copy's mscore binary> <score>\n")
        return 2
    binary, score = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    guard = subprocess.run([shutil.which("sh") or "sh", str(HERE / "tools" / "test-app.sh"), str(binary), str(score)],
                           stdin=subprocess.DEVNULL, check=False)
    if guard.returncode:
        return guard.returncode
    launch_log = sibling("metronome-pick.py").launch_log
    pick = f"{PROBE_PREFIX}{uuid.uuid4().hex}"
    work = pathlib.Path(tempfile.mkdtemp())
    try:
        plain = work / "plain.mscz"
        without_audio_settings(score, plain)
        set_slots({"position/1": {"resourceMeta": {"id": pick, "type": "fluid_soundfont", "vendor": "Fluid",
                                                    "attributes": {}}}})
        remembered_log, _ = launch_log(binary, plain)
        set_slots(None)
        control_log, _ = launch_log(binary, plain)
    finally:
        set_slots(None)
        shutil.rmtree(work, ignore_errors=True)
    applied = f"Not found: {pick}" in remembered_log
    named = PROBE_PREFIX in control_log
    if not applied:
        sys.stderr.write(f"the remembered pick {pick} never reached the audio engine\n")
        return 1
    if named:
        sys.stderr.write("a launch with no remembered pick still asked for one: the probe cannot tell them apart\n")
        return 1
    sys.stdout.write("ok (the remembered staff-1 pick reached the audio engine; with none remembered, none was asked for)\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
