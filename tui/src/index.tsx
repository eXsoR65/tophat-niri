import { createCliRenderer } from "@opentui/core";
import { createRoot } from "@opentui/react";
import { App } from "./app.tsx";

// The renderer is created once and destroyed on every shutdown path; the React
// root does not own it (see the OpenTUI lifecycle docs).
const renderer = await createCliRenderer();

const shutdown = () => {
  renderer.destroy();
  process.exit(0);
};

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);

createRoot(renderer).render(<App />);
