"""Derive the piano key layer colours: Okabe-Ito and Kelly's maximum-contrast colours, kept only when bright enough to
read on a black key and saturated enough to read on a white one, then ordered so no 2 neighbours are close in hue.

usage: python3 palette.py
Prints 1 colour per line, in layer order, as `#RRGGBB luminance saturation hue`.
"""

import colorsys
import sys

OKABE_ITO = ["#E69F00", "#56B4E9", "#009E73", "#F0E442", "#0072B2", "#D55E00", "#CC79A7"]
KELLY = [
    "#F3C300", "#875692", "#F38400", "#A1CAF1", "#BE0032", "#C2B280", "#848482", "#008856", "#E68FAC", "#0067A5",
    "#F99379", "#604E97", "#F6A600", "#B3446C", "#DCD300", "#882D17", "#8DB600", "#654522", "#E25822", "#2B3D26",
]
MIN_LUMINANCE = 0.2
MIN_SATURATION = 0.4
MIN_HUE_GAP = 0.05
SRGB_KNEE = 0.04045
SRGB_SLOPE = 12.92
SRGB_GAMMA = 2.4


def channel(value: float) -> float:
    """Linearise 1 sRGB channel.

    Args:
        value: The channel in 0 to 1.

    Returns:
        Its linear-light value.

    """
    return value / SRGB_SLOPE if value <= SRGB_KNEE else ((value + 0.055) / 1.055) ** SRGB_GAMMA


def measure(colour: str) -> tuple[float, float, float]:
    """Measure a colour.

    Args:
        colour: `#RRGGBB`.

    Returns:
        Its relative luminance, HSV saturation and hue.

    """
    red, green, blue = (int(colour[at : at + 2], 16) / 255 for at in (1, 3, 5))
    luminance = 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    hue, saturation, _ = colorsys.rgb_to_hsv(red, green, blue)
    return luminance, saturation, hue


def gap(first: float, second: float) -> float:
    """Distance between 2 hues on the colour wheel.

    Args:
        first: A hue in 0 to 1.
        second: Another.

    Returns:
        The shorter way round, in 0 to 0.5.

    """
    apart = abs(first - second)
    return min(apart, 1 - apart)


def main() -> int:
    """Print the ordered palette.

    Returns:
        0.

    """
    kept: list[tuple[str, float, float, float]] = []
    for colour in OKABE_ITO + KELLY:
        luminance, saturation, hue = measure(colour)
        if luminance < MIN_LUMINANCE or saturation < MIN_SATURATION:
            continue
        if any(gap(hue, other[3]) < MIN_HUE_GAP for other in kept):
            continue
        kept.append((colour, luminance, saturation, hue))
    ordered = [kept.pop(0)]
    while kept:
        best = max(kept, key=lambda entry: min(gap(entry[3], chosen[3]) for chosen in ordered[-2:]))
        kept.remove(best)
        ordered.append(best)
    for colour, luminance, saturation, hue in ordered:
        sys.stdout.write(f"{colour} {luminance:.2f} {saturation:.2f} {hue * 360:.0f}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
