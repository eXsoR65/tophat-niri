// Pure configuration state and argv construction.
//
// Everything the TUI decides about *how* to run the installer lives here, so it
// can be tested without a terminal or a child process. The TUI never
// reimplements installer logic: it produces flags and lets install.sh do the
// work.

import { STAGES, type StageName } from "./stages.ts";

export type Config = {
  dryRun: boolean;
  verbose: boolean;
  force: boolean;
  acceptRemovals: boolean;
  targetUser: string;
  selected: Set<StageName>;
};

export function defaultConfig(targetUser = ""): Config {
  return {
    dryRun: false,
    verbose: false,
    force: false,
    acceptRemovals: false,
    targetUser,
    selected: new Set<StageName>(),
  };
}

/** Toggle a stage in or out of the explicit selection. */
export function toggleStage(config: Config, stage: StageName): Config {
  const selected = new Set(config.selected);
  if (selected.has(stage)) {
    selected.delete(stage);
  } else {
    selected.add(stage);
  }
  return { ...config, selected };
}

/** The user the installer will act on: `sudo` invoker if present. */
export function detectedUser(env: Record<string, string | undefined> = process.env): string {
  return env.SUDO_USER ?? env.USER ?? "";
}

/**
 * Build the installer argv.
 *
 * No selection means every stage, which is also what `--select` with all seven
 * names would say, so that case omits the flag rather than spelling it out.
 * Flags are emitted in a fixed order so the output is stable and testable.
 */
export function buildArgs(config: Config): string[] {
  const args: string[] = [];

  if (config.selected.size > 0 && config.selected.size < STAGES.length) {
    const ordered = STAGES.filter((stage) => config.selected.has(stage));
    args.push("--select", ordered.join(","));
  }

  if (config.dryRun) args.push("--dry-run");
  if (config.verbose) args.push("--verbose");
  if (config.force) args.push("--force");
  if (config.acceptRemovals) args.push("--accept-package-removals");

  const user = config.targetUser.trim();
  if (user !== "") args.push("--target-user", user);

  return args;
}
