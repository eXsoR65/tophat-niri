#!/usr/bin/env python3
"""Every action a workflow executes must be immutable.

A tag can be moved; a 40-character commit SHA cannot. Dependabot raises the PRs
that bump the pins, so they stay current instead of fossilising.

This parses the workflow YAML instead of scanning it line by line. Three review
rounds produced findings that a line scanner cannot fix honestly - flow
mappings (`- {uses: x@v1}`), folded scalars (`uses: >-`), quoted keys, and block
headers with trailing comments - because each one is YAML the scanner only
approximates. A parser resolves all of them, and correctly ignores a `run: |`
script that merely contains the text "uses:".

A value is accepted only if it is:
  - a local action            (./... or ../...)
  - a digest-pinned image     (docker://...@sha256:...)
  - a repository ref pinned to a 40-character commit SHA
Anything else fails, including shapes nobody anticipated.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover - reported by the shell wrapper too
    sys.exit("FAIL: PyYAML is required (python3 -c 'import yaml')")

PINNED = re.compile(r"^[^\s@]+@[0-9a-f]{40}$")


def uses_values(node):
    """Yield every `uses:` value anywhere in the document."""
    if isinstance(node, dict):
        for key, value in node.items():
            if key == "uses":
                yield value
            yield from uses_values(value)
    elif isinstance(node, list):
        for item in node:
            yield from uses_values(item)


def is_allowed(ref: object) -> bool:
    if not isinstance(ref, str):
        return False
    ref = ref.strip()
    if ref.startswith(("./", "../")):
        return True
    if ref.startswith("docker://"):
        return "@sha256:" in ref
    return bool(PINNED.match(ref))


def main(argv: list[str]) -> int:
    root = Path(argv[1]) if len(argv) > 1 else Path(__file__).resolve().parent.parent
    workflows = sorted(root.glob(".github/workflows/*.yml")) + sorted(
        root.glob(".github/workflows/*.yaml")
    )

    if not workflows:
        print(f"FAIL: no workflow files found under {root}/.github/workflows", file=sys.stderr)
        return 1

    bad: list[tuple[Path, object]] = []
    total = 0

    for path in workflows:
        try:
            documents = list(yaml.safe_load_all(path.read_text()))
        except yaml.YAMLError as exc:
            print(f"FAIL: cannot parse {path}: {exc}", file=sys.stderr)
            return 1

        for document in documents:
            for ref in uses_values(document):
                total += 1
                if not is_allowed(ref):
                    bad.append((path, ref))

    if bad:
        print(
            "FAIL: workflow references must be pinned "
            "(40-character commit SHA, or a docker digest):",
            file=sys.stderr,
        )
        for path, ref in bad:
            print(f"  {path}: {ref}", file=sys.stderr)
        return 1

    print(f"check_action_pins.sh: PASS ({len(workflows)} workflow file(s), {total} reference(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
