// Where the installer keeps its log and state.
//
// These default to the same paths install.sh exports, and are overridable so the
// TUI can be driven against a scratch directory in tests and in CI.

export type Paths = {
  root: string;
  logDir: string;
  stateDir: string;
  installScript: string;
};

export function resolvePaths(
  env: Record<string, string | undefined> = process.env,
  root: string = process.cwd(),
): Paths {
  return {
    root,
    logDir: env.TOPHAT_LOG_DIR ?? "/var/log/tophat",
    stateDir: env.TOPHAT_STATE_DIR ?? "/var/lib/tophat",
    installScript: env.TOPHAT_INSTALL ?? `${root}/install.sh`,
  };
}

/** Newest log: the `latest.log` symlink the installer maintains. */
export function latestLog(paths: Paths): string {
  return `${paths.logDir}/latest.log`;
}
