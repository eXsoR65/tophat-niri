// Log tailing helpers. `run_logged` writes everything to $SETUP_LOG, so the TUI
// only has to follow one file - no Bash changes are needed for progress.

/** The last `max` lines of `text`, never including a trailing empty line. */
export function tailLines(text: string, max: number): string[] {
  if (max <= 0) return [];
  const lines = text.split("\n");
  if (lines.length > 0 && lines[lines.length - 1] === "") lines.pop();
  return lines.slice(-max);
}

/**
 * The part of `next` that was appended since `previous`.
 *
 * Logs are rewritten in place by the shell, so the common case is a pure append.
 * If the file shrank or changed earlier content (truncation, rotation) the whole
 * text is returned instead, so nothing is silently dropped.
 */
export function appendedSince(previous: string, next: string): string {
  if (previous === "") return next;
  if (next.startsWith(previous)) return next.slice(previous.length);
  return next;
}
