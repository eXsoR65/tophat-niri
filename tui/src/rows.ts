// The config screen's rows, in display order: the three toggles, every stage, then
// the start action. Kept separate from the view so the keyboard reducer can be
// tested without rendering anything.

import { STAGES, type StageName } from "./stages.ts";

export type FlagKey = "dryRun" | "verbose" | "acceptRemovals";

export type Row =
  | { kind: "flag"; key: FlagKey }
  | { kind: "stage"; stage: StageName }
  | { kind: "start" };

export const ROWS: Row[] = [
  { kind: "flag", key: "dryRun" },
  { kind: "flag", key: "verbose" },
  { kind: "flag", key: "acceptRemovals" },
  ...STAGES.map((stage) => ({ kind: "stage", stage }) as Row),
  { kind: "start" },
];

export const FLAG_LABELS: Record<FlagKey, string> = {
  dryRun: "Dry run (change nothing)",
  verbose: "Verbose (show command output)",
  acceptRemovals: "Allow package removals",
};
