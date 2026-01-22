#
# Git utilities
#
# Copyright (c) 2025 Shareef Jalloq
# SPDX-License-Identifier: BSD-2-Clause
#

from pathlib import Path


def find_project_root(start_path: Path) -> Path | None:
    """
    Find the project root by walking up from start_path.

    Looks for pyproject.toml or .git directory as indicators of the project root.

    Args:
        start_path: Path to start searching from

    Returns:
        Path to the project root, or None if not found
    """
    current = start_path.resolve()
    for parent in [current] + list(current.parents):
        if (parent / "pyproject.toml").exists() or (parent / ".git").exists():
            return parent
    return None
