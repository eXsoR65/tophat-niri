// Height-aware row windows.
//
// The config screen has more rows than a 24-line terminal can show (flags, the
// target-user field, seven stages, and Start). Rather than letting the renderer
// clip the list - which hid Start entirely and overlapped lines on the Run
// screen - keep the cursor visible inside a window and tell the user it is
// windowed.

export type Window = {
  start: number;
  end: number;
};

/** Truncate a line to the cells available, so it cannot wrap into extra rows. */
export function clipLine(text: string, maxWidth: number): string {
  if (maxWidth <= 0) return "";
  // Tabs expand to the next tab stop, and CR/ESC can move the cursor; either
  // would defeat the width budget even after truncation. Render controls as
  // spaces so every remaining character occupies one cell.
  const safe = text.replace(/[\u0000-\u001f\u007f]/g, " ");
  const characters = [...safe];
  if (characters.length <= maxWidth) return safe;
  if (maxWidth === 1) return "…";
  return `${characters.slice(0, maxWidth - 1).join("")}…`;
}

/** The slice of `length` rows that keeps `cursor` visible in `capacity` rows. */
export function visibleWindow(cursor: number, length: number, capacity: number): Window {
  const size = Math.max(1, Math.min(length, Math.floor(capacity)));
  if (length === 0) return { start: 0, end: 0 };

  const maxStart = Math.max(0, length - size);
  const start = Math.min(Math.max(0, cursor - Math.floor(size / 2)), maxStart);
  return { start, end: start + size };
}
