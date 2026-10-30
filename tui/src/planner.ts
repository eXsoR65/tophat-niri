// Stage-plan and package-list reading for the config screen.
//
// The dependency graph lives in lib/stages.sh and is asked for, never mirrored:
// `install.sh --print-plan` prints the resolved stage list, so this file only
// builds its arguments and parses its output.

import { STAGES, type StageName } from "./stages.ts";
import type { Config } from "./config.ts";
import type { Paths } from "./paths.ts";
import { readFileSync } from "node:fs";

/** Arguments for `install.sh --print-plan`, mirroring the selection only. */
export function planArgs(config: Config): string[] {
  if (config.selected.size === 0 || config.selected.size >= STAGES.length) return [];
  const ordered = STAGES.filter((stage) => config.selected.has(stage));
  return ["--select", ordered.join(",")];
}

/** Parse `--print-plan` output, keeping only stages we know about. */
export function parsePlan(text: string): StageName[] {
  const seen = new Set<StageName>();
  for (const line of text.split("\n")) {
    const name = line.trim() as StageName;
    if (STAGES.includes(name)) seen.add(name);
  }
  return [...seen];
}

/**
 * Stages the plan pulls in that the user did not pick: the "dependency" label.
 * With no explicit selection everything is intended, so nothing is a dependency.
 */
export function dependencies(plan: StageName[], config: Config): Set<StageName> {
  if (config.selected.size === 0) return new Set();
  return new Set(plan.filter((stage) => !config.selected.has(stage)));
}

/** Parse a `packages/*.packages` file: one entry per line, `#` comments. */
export function parseListFile(text: string): string[] {
  return text
    .split("\n")
    .map((line) => line.replace(/#.*$/, "").trim())
    .filter((line) => line !== "");
}

/** The packages the removals toggle would remove, read from the repo. */
export function loadRemovals(paths: Paths): string[] {
  try {
    return parseListFile(readFileSync(`${paths.root}/packages/remove-replaced.packages`, "utf8"));
  } catch {
    return [];
  }
}

/** Ask the installer for the resolved plan. */
export async function fetchPlan(paths: Paths, config: Config): Promise<StageName[]> {
  const args = planArgs(config);
  const proc = Bun.spawn(["bash", paths.installScript, "--print-plan", ...args], {
    cwd: paths.root,
    stdout: "pipe",
    stderr: "pipe",
  });
  const [output, status] = await Promise.all([new Response(proc.stdout).text(), proc.exited]);
  if (status !== 0) return [];
  return parsePlan(output);
}
