"""Refuse an assignment to a positioner's own implicit size in compiled QML.

usage: python3 qml-readonly.py <source tree>
A Column, Row, Grid or Flow computes its implicitWidth and implicitHeight from its children, so QML refuses an
assignment to them at launch and the whole window fails to load, while the build compiles cleanly.
"""

import pathlib
import re
import sys

POSITIONERS = frozenset({"Column", "Row", "Grid", "Flow"})
QML_NAME = re.compile(r"([\w./-]+\.qml)\b")
OBJECT_OPEN = re.compile(r"([A-Z][A-Za-z0-9_.]*)\s*\{")
IMPLICIT_SIZE = re.compile(r"implicit(Width|Height)\s*:")
ARGC = 2


def compiled_qml(src: pathlib.Path) -> list[pathlib.Path]:
    """List every QML file a CMake list under the tree names.

    Args:
        src: The tree's src folder.

    Returns:
        The existing QML files, sorted.

    """
    names: set[pathlib.Path] = set()
    for cmake in src.rglob("CMakeLists.txt"):
        text = cmake.read_text(encoding="utf-8", errors="replace")
        names.update((cmake.parent / match.group(1)).resolve() for match in QML_NAME.finditer(text))
    return sorted(path for path in names if path.is_file() and "tests" not in path.parts)


def assignments(text: str) -> list[int]:
    """Find lines assigning an implicit size directly inside a positioner.

    Args:
        text: A QML file's text.

    Returns:
        The 1-based line numbers of each such assignment.

    """
    stack: list[str | None] = []
    found: list[int] = []
    for number, line in enumerate(text.splitlines(), 1):
        stripped = line.strip()
        if IMPLICIT_SIZE.match(stripped) and stack and stack[-1] in POSITIONERS:
            found.append(number)
        opened = OBJECT_OPEN.match(stripped)
        for index in range(stripped.count("{")):
            stack.append(opened.group(1).split(".")[-1] if opened and index == 0 else None)
        for _ in range(stripped.count("}")):
            if stack:
                stack.pop()
    return found


def main() -> int:
    """Check the tree named on the command line.

    Returns:
        0 when no positioner's implicit size is assigned, 1 otherwise, 2 on bad arguments.

    """
    if len(sys.argv) != ARGC:
        sys.stderr.write("usage: qml-readonly.py <source tree>\n")
        return 2
    src = pathlib.Path(sys.argv[1]) / "src"
    files = compiled_qml(src)
    if not files:
        sys.stderr.write("no compiled QML found: the check read nothing\n")
        return 1
    hits = [
        f"{path.relative_to(src.parent)}:{line}"
        for path in files
        for line in assignments(path.read_text(encoding="utf-8", errors="replace"))
    ]
    if hits:
        sys.stderr.write("implicit size assigned inside a Column, Row, Grid or Flow, which QML refuses at launch:\n")
        sys.stderr.write("\n".join(hits) + "\n")
        return 1
    sys.stdout.write(f"ok ({len(files)} QML files)\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
