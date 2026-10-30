import { createCliRenderer } from "@opentui/core";
import { createRoot } from "@opentui/react";
import { App } from "./app.tsx";

// OpenTUI installs its own handlers for SIGINT/SIGTERM/SIGHUP and restores the
// terminal on every one of them, so this file deliberately does not trap
// signals: a custom handler that calls process.exit() would skip that cleanup
// and can leave the terminal in raw/alternate-screen mode.
const renderer = await createCliRenderer({ exitOnCtrlC: true });

createRoot(renderer).render(<App />);
