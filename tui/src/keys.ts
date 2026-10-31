// Keyboard handling as a pure function.
//
// The component decides what to *do* (start, destroy the renderer, signal the
// child); this decides what the key *means*, which is the part that is easy to
// get wrong and impossible to test through a real terminal in CI.

import type { Row } from "./rows.ts";
import type { Screen } from "./app.ts";

export type Action =
  | { type: "none" }
  | { type: "move"; delta: number }
  | { type: "toggle-row"; row: Row }
  | { type: "start" }
  | { type: "quit" }
  | { type: "abort" }
  | { type: "retry" };

export function keyAction(screen: Screen, keyName: string, cursor: number, rows: Row[]): Action {
  if (screen === "run") {
    return keyName === "q" ? { type: "abort" } : { type: "none" };
  }

  if (screen === "done") {
    if (keyName === "q") return { type: "quit" };
    // Retrying only exists once a run has finished, and only makes sense for a
    // failure; the component decides whether there is a stage to retry.
    if (keyName === "r") return { type: "retry" };
    return { type: "none" };
  }

  switch (keyName) {
    case "up":
      return { type: "move", delta: -1 };
    case "down":
      return { type: "move", delta: 1 };
    case "space": {
      const row = rows[cursor];
      if (!row) return { type: "none" };
      return row.kind === "start" ? { type: "start" } : { type: "toggle-row", row };
    }
    case "return":
    case "enter":
      return { type: "start" };
    case "q":
      return { type: "quit" };
    default:
      return { type: "none" };
  }
}

/** Cursor movement with wrap-around. */
export function moveCursor(cursor: number, delta: number, length: number): number {
  if (length === 0) return 0;
  return (cursor + delta + length) % length;
}
