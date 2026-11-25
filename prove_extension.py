"""Prove the seating extension run through --serve saves the same score and render as a fresh launch.

usage: prove_extension.py <mscore binary> <extension uri> <out dir> <score.mscz>...
"""

import json
import pathlib
import subprocess
import sys
import time
import zipfile

from prove import layout


def mscx(path: pathlib.Path) -> str:
    with zipfile.ZipFile(path) as archive:
        return next(archive.read(n).decode() for n in archive.namelist() if n.endswith(".mscx"))


def main() -> None:
    binary, uri, out = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3])
    scores = [pathlib.Path(p) for p in sys.argv[4:]]
    out.mkdir(parents=True, exist_ok=True)
    began = time.monotonic()
    for i, score in enumerate(scores):
        subprocess.run(
            [binary, "--extension", uri, "-o", str(out / f"fresh-{i}.mscz"), str(score)],
            stdin=subprocess.DEVNULL,
            capture_output=True,
            check=True,
        )
        subprocess.run(
            [binary, "-o", str(out / f"fresh-{i}.pdf"), str(out / f"fresh-{i}.mscz")],
            stdin=subprocess.DEVNULL,
            capture_output=True,
            check=True,
        )
    launched = time.monotonic() - began
    server = subprocess.Popen([binary, "--serve"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    if server.stdin is None or server.stdout is None:
        msg = "the server opened no pipes"
        raise SystemExit(msg)
    sent, answers = server.stdin, server.stdout
    began = time.monotonic()
    requests = []
    for i, score in enumerate(scores):
        seat = out / f"seat-{i}.json"
        seat.write_text(json.dumps([{"in": str(score), "out": str(out / f"served-{i}.mscz")}]))
        render = out / f"render-{i}.json"
        render.write_text(json.dumps([{"in": str(out / f"served-{i}.mscz"), "out": str(out / f"served-{i}.pdf")}]))
        requests += [{"id": f"s{i}", "job": str(seat), "extension": uri}, {"id": f"r{i}", "job": str(render)}]
    for request in requests:
        sent.write(json.dumps(request) + "\n")
        sent.flush()
        while not (line := answers.readline()).startswith(request["id"] + " "):
            if not line:
                msg = "server exited"
                raise SystemExit(msg)
        if " ok" not in line:
            raise SystemExit(line)
    served = time.monotonic() - began
    sent.close()
    server.wait(timeout=60)
    differing = [
        str(s)
        for i, s in enumerate(scores)
        if mscx(out / f"fresh-{i}.mscz") != mscx(out / f"served-{i}.mscz")
        or layout(out / f"fresh-{i}.pdf") != layout(out / f"served-{i}.pdf")
    ]
    sys.stdout.write(f"{len(scores)} scores seated and rendered: launched {launched:.1f} s, served {served:.1f} s" + "\n")
    sys.stdout.write(f"score or layout differs for {len(differing)}: {differing}" + "\n")


if __name__ == "__main__":
    main()
