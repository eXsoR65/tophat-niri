// Where the installer keeps its log and state, and where the checkout is.
//
// The root comes from the module's own location, not from the current directory:
// `./tophat` may be invoked from anywhere (a symlink on PATH, another project's
// shell), and resolving `install.sh` against `process.cwd()` pointed at a file
// that did not exist.

import { fileURLToPath } from "node:url";

export type Paths = {
  root: string;
  logDir: string;
  stateDir: string;
  installScript: string;
};

// tui/src/paths.ts -> the repository root. URL resolution keeps a trailing
// separator, which would turn every derived path into a doubled slash.
const MODULE_ROOT = fileURLToPath(new URL("../..", import.meta.url)).replace(/\/+$/, "");

export function resolvePaths(
  env: Record<string, string | undefined> = process.env,
  root?: string,
): Paths {
  const base = root ?? env.TOPHAT_ROOT ?? MODULE_ROOT;
  return {
    root: base,
    logDir: env.TOPHAT_LOG_DIR ?? "/var/log/tophat",
    stateDir: env.TOPHAT_STATE_DIR ?? "/var/lib/tophat",
    installScript: env.TOPHAT_INSTALL ?? `${base}/install.sh`,
  };
}

/** Newest log: the `latest.log` symlink the installer maintains. */
export function latestLog(paths: Paths): string {
  return `${paths.logDir}/latest.log`;
}
