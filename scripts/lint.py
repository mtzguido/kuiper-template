#!/usr/bin/env python3
"""Check lightweight repository hygiene without third-party dependencies."""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
IGNORED_DIRS = {
    ".git",
    ".kuiper",
    ".tools",
    ".venv",
    "obj",
    "__pycache__",
}


def source_files() -> list[Path]:
    files: list[Path] = []
    for directory, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = sorted(name for name in dirnames if name not in IGNORED_DIRS)
        files.extend(
            Path(directory, name)
            for name in sorted(filenames)
            if name != ".depend"
            and not name.endswith(".smt2")
            and not Path(directory, name).is_symlink()
        )
    return files


def main() -> int:
    errors: list[str] = []
    for path in source_files():
        data = path.read_bytes()
        if b"\0" in data:
            continue
        relative = path.relative_to(ROOT)
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError:
            errors.append(f"{relative}: is not UTF-8 text")
            continue

        if "\r" in text:
            errors.append(f"{relative}: contains carriage returns")
        if text and not text.endswith("\n"):
            errors.append(f"{relative}: missing final newline")
        for number, line in enumerate(text.splitlines(), start=1):
            if line.endswith((" ", "\t")):
                errors.append(f"{relative}:{number}: trailing whitespace")

        if path.suffix in {".py", ".sh"} and text.startswith("#!"):
            if not os.access(path, os.X_OK):
                errors.append(f"{relative}: shebang script is not executable")

        try:
            if path.suffix == ".py":
                compile(text, str(relative), "exec")
            elif path.suffix == ".json":
                json.loads(text)
        except (SyntaxError, json.JSONDecodeError) as error:
            errors.append(f"{relative}: {error}")

        if path.suffix == ".sh" or path.name == "fstar.sh":
            result = subprocess.run(
                ["bash", "-n", str(path)],
                check=False,
                capture_output=True,
                text=True,
            )
            if result.returncode:
                errors.append(f"{relative}: {result.stderr.strip()}")

    if errors:
        print("\n".join(errors))
        return 1
    print("Lint checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
