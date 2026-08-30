import { cleanup, render, screen, waitFor } from "@solidjs/testing-library";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it } from "vitest";
import { DiffViewer, languageForPath, splitDiffFiles } from "./diffViewer";

const DIFF = [
  "diff --git a/a.c b/a.c",
  "index 1111111..2222222 100644",
  "--- a/a.c",
  "+++ b/a.c",
  "@@ -10,2 +10,2 @@",
  "-old();",
  "+new();",
  " same();",
  "diff --git a/b.rs b/b.rs",
  "new file mode 100644",
  "--- /dev/null",
  "+++ b/b.rs",
  "@@ -0,0 +1 @@",
  "+fn main() {}",
  "",
].join("\n");

afterEach(cleanup);

describe("diff file parsing", () => {
  it("splits files and infers supported Shiki languages", () => {
    const files = splitDiffFiles(DIFF);

    expect(files).toHaveLength(2);
    expect(files[0]).toMatchObject({ label: "a.c", language: "c" });
    expect(files[1]).toMatchObject({ label: "b.rs", language: "rust" });
    expect(files[0]?.text).toContain("-old();");
    expect(files[1]?.text).toContain("+fn main() {}");

    expect(languageForPath("arch/arm64/boot/example.dtsi")).toBe("c");
    expect(languageForPath("Documentation/example.yaml")).toBe("yaml");
    expect(languageForPath("scripts/tool.py")).toBe("python");
    expect(languageForPath("Makefile")).toBe("makefile");
    expect(languageForPath("assets/unknown.kernel-data")).toBe("diff");
  });
});

describe("DiffViewer", () => {
  it("switches between structured and raw views and collapses the whole diff", async () => {
    const user = userEvent.setup();
    const { container } = render(() => <DiffViewer diff={DIFF} />);

    expect(container.querySelectorAll("details.diff-file")).toHaveLength(2);
    expect(screen.getByRole("button", { name: "Collapse diff section" })).toHaveAttribute(
      "aria-expanded",
      "true",
    );

    await user.click(screen.getByRole("checkbox", { name: "Raw" }));
    expect(container.querySelectorAll("details.diff-file")).toHaveLength(0);
    expect(container.querySelector(".diff-viewer-raw")?.textContent).toBe(DIFF);

    await user.click(screen.getByRole("button", { name: "Collapse diff section" }));
    expect(container.querySelector(".diff-viewer-raw")).not.toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "Expand diff section" }));
    expect(container.querySelector(".diff-viewer-raw")?.textContent).toBe(DIFF);

    await user.click(screen.getByRole("checkbox", { name: "Raw" }));
    await waitFor(() => {
      expect(container.querySelector(".diff-line-gutter")).toBeInTheDocument();
    });
    expect(container.querySelector(".diff-deletion .diff-old-line")).toHaveTextContent("10");
    expect(container.querySelector(".diff-addition .diff-new-line")).toHaveTextContent("10");
    expect(container.querySelector(".diff-context .diff-old-line")).toHaveTextContent("11");
    expect(container.querySelector(".diff-context .diff-new-line")).toHaveTextContent("11");
  });
});
