"""Refuse a floating panel capture whose content leaves an empty band at its right or bottom edge.

usage: python panel_band.py <window capture png>...
A floating window sized to its content shows ink close to every edge; a window that grew to its content and never shrank
back shows its content in 1 corner and a band of plain background beside it. The band is the run of rows from the bottom
(or columns from the right) whose every pixel matches the background colour sampled at that corner, measured as a share
of the window; a share above BAND_SHARE refuses the capture. Each capture keeps a margin of the frame's own border and
shadow, which stays far below the share.
"""

import pathlib
import sys

import pymupdf

BAND_SHARE = 0.08
TOLERANCE = 12
ARGC_MIN = 2


def pixel(pix: pymupdf.Pixmap, x: int, y: int) -> tuple[int, ...]:
    """Read 1 pixel's colour channels.

    Args:
        pix: The capture.
        x: Column.
        y: Row.

    Returns:
        The colour channels, alpha left out.

    """
    return tuple(int(channel) for channel in pix.pixel(x, y)[:3])


def plain(pix: pymupdf.Pixmap, cells: list[tuple[int, int]], background: tuple[int, ...]) -> bool:
    """Tell whether every given pixel matches the background.

    Args:
        pix: The capture.
        cells: The pixels to check, as column and row.
        background: The background colour.

    Returns:
        True when every pixel lies within the tolerance of the background.

    """
    return all(max(abs(a - b) for a, b in zip(pixel(pix, x, y), background, strict=True)) <= TOLERANCE for x, y in cells)


def bands(path: pathlib.Path) -> tuple[float, float]:
    """Measure the empty band at a capture's right and bottom edges, inside its frame.

    Args:
        path: The window capture.

    Returns:
        The right band's share of the width and the bottom band's share of the height.

    """
    pix = pymupdf.Pixmap(str(path))
    width, height = int(pix.width), int(pix.height)
    inset_x, inset_y = width // 50 + 2, height // 50 + 2
    background = pixel(pix, width - inset_x, height - inset_y)
    rows = range(inset_y, height - inset_y)
    columns = range(inset_x, width - inset_x)
    right = 0
    for x in range(width - inset_x, inset_x, -1):
        if not plain(pix, [(x, y) for y in rows[:: max(1, len(rows) // 200)]], background):
            break
        right += 1
    bottom = 0
    for y in range(height - inset_y, inset_y, -1):
        if not plain(pix, [(x, y) for x in columns[:: max(1, len(columns) // 200)]], background):
            break
        bottom += 1
    return right / width, bottom / height


def main() -> int:
    """Check every capture named on the command line.

    Returns:
        0 when no capture shows a band, 1 otherwise, 2 on bad arguments.

    """
    if len(sys.argv) < ARGC_MIN:
        sys.stderr.write("usage: panel_band.py <window capture png>...\n")
        return 2
    refused = []
    for name in sys.argv[1:]:
        right, bottom = bands(pathlib.Path(name))
        if max(right, bottom) > BAND_SHARE:
            refused.append(f"{name}: empty band {right:.0%} of the width at the right, {bottom:.0%} of the height below")
    if refused:
        sys.stderr.write("\n".join(refused) + "\n")
        return 1
    sys.stdout.write(f"ok ({len(sys.argv) - 1} captures, none with an empty band)\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
