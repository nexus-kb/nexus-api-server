import { describe, expect, it } from "vitest";
import { parseMessageBody } from "./messageBody";

describe("parseMessageBody", () => {
  it("extracts a cover-letter diffstat", () => {
    const body = [
      "Cover letter",
      "---",
      " drivers/media/example.c | 3 ++-",
      " MAINTAINERS             | 1 +",
      " 2 files changed, 3 insertions(+), 1 deletion(-)",
      "",
      "base-commit: deadbeef",
      "",
    ].join("\n");

    expect(parseMessageBody(body)).toEqual([
      { kind: "text", text: "Cover letter\n---\n" },
      {
        kind: "diffstat",
        text:
          " drivers/media/example.c | 3 ++-\n" +
          " MAINTAINERS             | 1 +\n" +
          " 2 files changed, 3 insertions(+), 1 deletion(-)\n",
      },
      { kind: "text", text: "\nbase-commit: deadbeef\n" },
    ]);
  });

  it("groups all files into one diff segment and preserves the mail footer", () => {
    const body = [
      "Commit message",
      "---",
      " a.c | 2 +-",
      " b.rs | 1 +",
      " 2 files changed, 2 insertions(+), 1 deletion(-)",
      "diff --git a/a.c b/a.c",
      "index 1111111..2222222 100644",
      "--- a/a.c",
      "+++ b/a.c",
      "@@ -1 +1 @@",
      "-old",
      "+new",
      "diff --git a/b.rs b/b.rs",
      "new file mode 100644",
      "--- /dev/null",
      "+++ b/b.rs",
      "@@ -0,0 +1 @@",
      "+fn main() {}",
      "-- ",
      "2.47.3",
      "",
    ].join("\n");

    const segments = parseMessageBody(body);

    expect(segments.map((segment) => segment.kind)).toEqual([
      "text",
      "diffstat",
      "diff",
      "text",
    ]);
    expect(segments[2]?.text).toContain("diff --git a/a.c b/a.c");
    expect(segments[2]?.text).toContain("diff --git a/b.rs b/b.rs");
    expect(segments[3]).toEqual({ kind: "text", text: "-- \n2.47.3\n" });
  });

  it("leaves ordinary messages unchanged", () => {
    expect(parseMessageBody("Reviewed-by: Developer <dev@example.com>")).toEqual([
      {
        kind: "text",
        text: "Reviewed-by: Developer <dev@example.com>",
      },
    ]);
  });
});
