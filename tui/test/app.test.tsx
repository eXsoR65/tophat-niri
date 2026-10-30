import { describe, expect, test } from "bun:test";
import { testRender } from "@opentui/react/test-utils";
import { App } from "../src/app.tsx";
import { defaultConfig } from "../src/config.ts";

async function frameOf(node: Parameters<typeof testRender>[0], width = 90, height = 30) {
  const setup = await testRender(node, { width, height });
  try {
    await setup.renderOnce();
    return setup.captureCharFrame();
  } finally {
    setup.renderer.destroy();
  }
}

describe("App", () => {
  test("config screen lists every stage and the start action", async () => {
    const frame = await frameOf(<App initialScreen="config" />);
    expect(frame).toContain("Tophat");
    for (const stage of ["preflight", "repos", "packaging", "config", "services", "extras", "finalize"]) {
      expect(frame).toContain(stage);
    }
    expect(frame).toContain("Start install");
    expect(frame).toContain("All stages selected");
  });

  test("config screen reflects a selection", async () => {
    const config = { ...defaultConfig("alice"), dryRun: true };
    config.selected.add("packaging");
    const frame = await frameOf(<App initialScreen="config" initialConfig={config} />);
    expect(frame).toContain("1 stage(s) selected");
    expect(frame).toContain("user: alice");
    expect(frame).toContain("Dry run");
  });

  test("run screen shows the stage board and waits for output", async () => {
    const frame = await frameOf(<App initialScreen="run" />);
    expect(frame).toContain("installing");
    expect(frame).toContain("waiting for output");
  });

  test("run screen marks completed stages", async () => {
    const frame = await frameOf(<App initialScreen="run" initialDone={["preflight", "repos"]} />);
    expect(frame).toContain("[x] preflight");
    expect(frame).toContain("[x] repos");
    expect(frame).toContain("[ ] packaging");
  });

  test("done screen reports success and marker count", async () => {
    const frame = await frameOf(
      <App initialScreen="done" initialExitCode={0} initialDone={["preflight", "repos"]} />,
    );
    expect(frame).toContain("Finished successfully");
    expect(frame).toContain("2 of 7");
    expect(frame).toContain("Reboot");
  });

  test("done screen reports a failure with its exit code", async () => {
    const frame = await frameOf(<App initialScreen="done" initialExitCode={1} />);
    expect(frame).toContain("Failed (exit 1)");
  });
});
