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
from itertools import chain
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover - reported by the shell wrapper too
    sys.exit("FAIL: PyYAML is required (python3 -c 'import yaml')")

PINNED = re.compile(r"^[^\s@]+@[0-9a-f]{40}$")


def action_refs(document):
    """Yield (location, value) for every node that executes an action.

    GitHub allows `uses` in exactly two places: a job (a reusable workflow call)
    and a step (an action). Walking every mapping instead would treat an input or
    environment variable that happens to be named `uses` as an action reference -
    `env: {uses: staging}` is not something to pin.
    """
    jobs = document.get("jobs") if isinstance(document, dict) else None
    if not isinstance(jobs, dict):
        return

    for job_name, job in jobs.items():
        if not isinstance(job, dict):
            continue

        if "uses" in job:
            yield f"jobs.{job_name}.uses", job["uses"]

        steps = job.get("steps")
        if not isinstance(steps, list):
            continue
        for index, step in enumerate(steps):
            if isinstance(step, dict) and "uses" in step:
                yield f"jobs.{job_name}.steps[{index}].uses", step["uses"]


def is_allowed(ref: object) -> bool:
    if not isinstance(ref, str):
        return False
    ref = ref.strip()
    if ref.startswith(("./", "../")):
        return True
    if ref.startswith("docker://"):
        return "@sha256:" in ref
    return bool(PINNED.match(ref))


def action_files(root: Path) -> list[Path]:
    """Workflow files, plus any composite action metadata in the tree.

    Composite actions (`action.yml` anywhere) also execute other actions in
    `runs.steps[].uses`, so a workflow-only scan would miss them the day one is
    added.
    """
    files = sorted(root.glob(".github/workflows/*.yml"))
    files += sorted(root.glob(".github/workflows/*.yaml"))
    for pattern in ("action.yml", "action.yaml"):
        files += sorted(
            path
            for path in root.glob(f"**/{pattern}")
            if ".git/" not in path.as_posix() and "node_modules/" not in path.as_posix()
        )
    return files


def composite_refs(document):
    """Yield references inside a composite action's `runs.steps[]`."""
    runs = document.get("runs") if isinstance(document, dict) else None
    steps = runs.get("steps") if isinstance(runs, dict) else None
    if not isinstance(steps, list):
        return
    for index, step in enumerate(steps):
        if isinstance(step, dict) and "uses" in step:
            yield f"runs.steps[{index}].uses", step["uses"]


def main(argv: list[str]) -> int:
    root = Path(argv[1]) if len(argv) > 1 else Path(__file__).resolve().parent.parent
    workflows = action_files(root)

    if not any(".github/workflows/" in path.as_posix() for path in workflows):
        print(f"FAIL: no workflow files found under {root}/.github/workflows", file=sys.stderr)
        return 1

    bad: list[tuple[Path, str, object]] = []
    total = 0

    for path in workflows:
        try:
            documents = list(yaml.safe_load_all(path.read_text()))
        except OSError as exc:
            print(f"FAIL: cannot read {path}: {exc}", file=sys.stderr)
            return 1
        except yaml.YAMLError as exc:
            print(f"FAIL: cannot parse {path}: {exc}", file=sys.stderr)
            return 1

        for document in documents:
            for location, ref in chain(action_refs(document), composite_refs(document)):
                total += 1
                if not is_allowed(ref):
                    bad.append((path, location, ref))

    if bad:
        print(
            "FAIL: workflow references must be pinned "
            "(40-character commit SHA, or a docker digest):",
            file=sys.stderr,
        )
        for path, location, ref in bad:
            print(f"  {path}: {location}: {ref}", file=sys.stderr)
        return 1

    print(f"check_action_pins.sh: PASS ({len(workflows)} action file(s), {total} reference(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
