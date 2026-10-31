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

/** The slice of `length` rows that keeps `cursor` visible in `capacity` rows. */
export function visibleWindow(cursor: number, length: number, capacity: number): Window {
  const size = Math.max(1, Math.min(length, Math.floor(capacity)));
  if (length === 0) return { start: 0, end: 0 };

  const maxStart = Math.max(0, length - size);
  const start = Math.min(Math.max(0, cursor - Math.floor(size / 2)), maxStart);
  return { start, end: start + size };
}
