"""Prove a served render equals a fresh launch's, position for position, and time both.

usage: prove.py <mscore binary> <out dir> <score.mscz>...
"""

import json
import pathlib
import subprocess
import sys
import time

import pymupdf


def layout(pdf: pathlib.Path) -> list[tuple[object, ...]]:
    found = []
    for number, page in enumerate(pymupdf.open(pdf).pages()):
        found += [(number, round(w[0], 3), round(w[1], 3), w[4]) for w in page.get_text("words")]
        for d in page.get_drawings():
            r = d["rect"]
            found.append((number, "path", round(r.x0, 3), round(r.y0, 3), round(r.x1, 3), round(r.y1, 3)))
        for b in page.get_text("rawdict")["blocks"]:
            for line in b.get("lines", []):
                for span in line["spans"]:
                    for c in span["chars"]:
                        found.append((number, "glyph", ord(c["c"]), round(c["origin"][0], 3), round(c["origin"][1], 3)))
    return sorted(found, key=repr)


def fresh(binary: str, score: pathlib.Path, out: pathlib.Path) -> float:
    began = time.monotonic()
    subprocess.run([binary, "-o", str(out), str(score)], stdin=subprocess.DEVNULL, capture_output=True, check=True)
    return time.monotonic() - began


def served(binary: str, jobs: list[tuple[pathlib.Path, pathlib.Path]], folder: pathlib.Path) -> float:
    server = subprocess.Popen([binary, "--serve"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    if server.stdin is None or server.stdout is None:
        msg = "the server opened no pipes"
        raise SystemExit(msg)
    sent, answers = server.stdin, server.stdout
    began = time.monotonic()
    for number, (score, out) in enumerate(jobs):
        job = folder / f"job{number}.json"
        job.write_text(json.dumps([{"in": str(score), "out": str(out)}]))
        sent.write(json.dumps({"id": str(number), "job": str(job)}) + "\n")
        sent.flush()
        while True:
            line = answers.readline()
            if not line:
                msg = "server exited"
                raise SystemExit(msg)
            if line.startswith(f"{number} "):
                if not line.startswith(f"{number} ok"):
                    msg = f"job failed: {line}"
                    raise SystemExit(msg)
                break
    spent = time.monotonic() - began
    sent.close()
    server.wait(timeout=60)
    return spent


def main() -> None:
    binary, out = sys.argv[1], pathlib.Path(sys.argv[2])
    scores = [pathlib.Path(p) for p in sys.argv[3:]]
    out.mkdir(parents=True, exist_ok=True)
    launched = sum(fresh(binary, s, out / f"fresh-{i}.pdf") for i, s in enumerate(scores))
    first = served(binary, [(s, out / f"served-{i}.pdf") for i, s in enumerate(scores)], out)
    second = served(binary, [(s, out / f"again-{i}.pdf") for i, s in reversed(list(enumerate(scores)))], out)
    differing = [
        str(s)
        for i, s in enumerate(scores)
        if not (layout(out / f"fresh-{i}.pdf") == layout(out / f"served-{i}.pdf") == layout(out / f"again-{i}.pdf"))
    ]
    sys.stdout.write(
        f"{len(scores)} scores: launched {launched:.1f} s, served {first:.1f} s, served reversed {second:.1f} s" + "\n",
    )
    sys.stdout.write(f"layout differs for {len(differing)}: {differing}" + "\n")


if __name__ == "__main__":
    main()
