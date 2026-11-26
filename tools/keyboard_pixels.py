"""Judge 2 captures of the score window for the piano keyboard.

The keyboard must still show after a pause, and a selected note's key must be lit in a colour with no grey anywhere on the
keys.

usage: python -m tools.keyboard_pixels <paused capture> <selected capture>
"""

import pathlib
import sys

import pymupdf

ARGC = 3
BAND_SHARE = 0.16
WHITE_FLOOR = 235
BLACK_CEILING = 100
GREY_SPREAD = 12
COLOUR_SPREAD = 40
MIN_WHITE_SHARE = 0.25
MIN_LIT_PIXELS = 40


def band(path: pathlib.Path) -> list[tuple[int, int, int]]:
    """Read the white keys' row of a capture.

    That is the top band's row with the most white or coloured pixels, which runs below the black keys and above the octave
    labels, so only key fill is judged, never a label's or a border's edge.

    Args:
        path: The capture.

    Returns:
        Every pixel of that row as red, green and blue.

    """
    pix = pymupdf.Pixmap(str(path))
    height = int(pix.height * BAND_SHARE)

    def row(y: int) -> list[tuple[int, int, int]]:
        return [(int(p[0]), int(p[1]), int(p[2])) for p in (pix.pixel(x, y) for x in range(pix.width))]

    def fill(pixels: list[tuple[int, int, int]]) -> int:
        return sum(1 for p in pixels if min(p) >= WHITE_FLOOR or max(p) - min(p) >= COLOUR_SPREAD)

    return max((row(y) for y in range(0, height, 2)), key=fill)


def main() -> int:
    """Check both captures.

    Returns:
        0 when the keyboard stayed and the selection is coloured, 1 otherwise, 2 on bad arguments.

    """
    if len(sys.argv) != ARGC:
        sys.stderr.write("usage: keyboard_pixels.py <paused capture> <selected capture>\n")
        return 2
    paused = band(pathlib.Path(sys.argv[1]))
    whites = sum(1 for r, g, b in paused if min(r, g, b) >= WHITE_FLOOR) / len(paused)
    selected = band(pathlib.Path(sys.argv[2]))
    coloured = sum(1 for p in selected if max(p) - min(p) >= COLOUR_SPREAD)
    grey = sum(1 for p in selected if max(p) - min(p) <= GREY_SPREAD and min(p) > BLACK_CEILING and max(p) < WHITE_FLOOR)
    failures = []
    if whites < MIN_WHITE_SHARE:
        failures.append(f"the keyboard is gone after the pause: {whites:.0%} of the top band is white key")
    if coloured < MIN_LIT_PIXELS:
        failures.append(f"no key lit in a colour for the selected note ({coloured} coloured pixels)")
    if grey >= MIN_LIT_PIXELS:
        failures.append(f"{grey} grey pixels on the keys: a lit key fell back to grey")
    if failures:
        sys.stderr.write("\n".join(failures) + "\n")
        return 1
    sys.stdout.write(
        f"ok (keyboard kept after the pause, {whites:.0%} white keys; selection lit in colour, {coloured} pixels)\n",
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
