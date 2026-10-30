// Stage names in execution order. This mirrors the Bash registry in
// lib/stages.sh, which remains the single source of truth: the TUI only uses
// this list to render a checklist and to build --select values, and asks the
// engine to resolve the real plan.

export const STAGES = [
  "preflight",
  "repos",
  "packaging",
  "config",
  "services",
  "extras",
  "finalize",
] as const;

export type StageName = (typeof STAGES)[number];
