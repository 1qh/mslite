"""Refuse a relative QML import that names a folder none of whose files a CMake list compiles in.

usage: python3 qml-imports.py <source tree>
QML resolves imports only at launch, so an import of a folder removed from the build compiles cleanly and opens no window.
"""

import pathlib
import re
import sys

QML_NAME = re.compile(r"([\w./-]+\.qml)\b")
RELATIVE_IMPORT = re.compile(r'\s*import\s+"([^"]+)"')
ARGC = 2


def listed(src: pathlib.Path) -> set[pathlib.Path]:
    """Collect every QML file a CMake list under the tree names.

    Args:
        src: The tree's src folder.

    Returns:
        The resolved paths of every QML file named in any CMakeLists.txt.

    """
    names: set[pathlib.Path] = set()
    for cmake in src.rglob("CMakeLists.txt"):
        text = cmake.read_text(encoding="utf-8", errors="replace")
        names.update((cmake.parent / match.group(1)).resolve() for match in QML_NAME.finditer(text))
    return names


def dead_imports(src: pathlib.Path) -> tuple[int, list[str]]:
    """Find relative imports in compiled QML whose folder holds no compiled QML.

    Args:
        src: The tree's src folder.

    Returns:
        The number of relative imports judged, and 1 line per dead import.

    """
    compiled = listed(src)
    judged = 0
    dead: list[str] = []
    for qml in sorted(compiled):
        if not qml.is_file() or "tests" in qml.parts:
            continue
        for number, line in enumerate(qml.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            match = RELATIVE_IMPORT.match(line)
            if match is None:
                continue
            judged += 1
            folder = (qml.parent / match.group(1)).resolve()
            if not any(path in compiled for path in folder.glob("*.qml")):
                dead.append(f"{qml.relative_to(src.parent)}:{number}: import {match.group(1)}")
    return judged, dead


def main() -> int:
    """Check the tree named on the command line.

    Returns:
        0 when every relative import resolves to compiled QML, 1 otherwise, 2 on bad arguments.

    """
    if len(sys.argv) != ARGC:
        sys.stderr.write("usage: qml-imports.py <source tree>\n")
        return 2
    judged, dead = dead_imports(pathlib.Path(sys.argv[1]) / "src")
    if judged == 0:
        sys.stderr.write("no relative QML import found: the check read nothing\n")
        return 1
    if dead:
        sys.stderr.write("relative QML imports of folders the build leaves out:\n" + "\n".join(dead) + "\n")
        return 1
    sys.stdout.write(f"ok ({judged} imports)\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
