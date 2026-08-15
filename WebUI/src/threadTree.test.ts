import { describe, expect, it } from "vitest";
import { buildThreadTree, mergeMessages } from "./threadTree";
import type { ThreadMessageSummary } from "./types";

function message(
  messageId: string,
  inReplyToMessageId: string | null = null,
  referenceMessageIds: string[] = [],
): ThreadMessageSummary {
  return {
    messageId,
    inReplyToMessageId,
    referenceMessageIds,
    availability: "available",
    subject: messageId,
    author: "Developer <developer@example.com>",
    sentAt: "2026-08-15T12:00:00Z",
    bodyPreview: messageId,
    patch: null,
  };
}

describe("buildThreadTree", () => {
  it("builds nested replies and preserves sibling input order", () => {
    const tree = buildThreadTree([
      message("root"),
      message("reply-b", "root"),
      message("reply-a", "root"),
      message("nested", "reply-b"),
    ]);

    expect(tree.map((node) => node.message.messageId)).toEqual(["root"]);
    expect(tree[0]?.children.map((node) => node.message.messageId)).toEqual([
      "reply-b",
      "reply-a",
    ]);
    expect(tree[0]?.children[0]?.children[0]?.message.messageId).toBe("nested");
  });

  it("keeps unrelated and unresolved messages as roots", () => {
    const tree = buildThreadTree([
      message("root-a"),
      message("orphan", "not-loaded"),
      message("root-b"),
    ]);

    expect(tree.map((node) => node.message.messageId)).toEqual([
      "root-a",
      "orphan",
      "root-b",
    ]);
  });

  it("falls back to the nearest loaded reference", () => {
    const tree = buildThreadTree([
      message("root"),
      message("reply", "missing-parent", ["root", "missing-parent"]),
    ]);

    expect(tree[0]?.children[0]?.message.messageId).toBe("reply");
  });

  it("breaks malformed parent cycles", () => {
    const tree = buildThreadTree([message("a", "b"), message("b", "a")]);

    expect(tree).toHaveLength(1);
    expect(tree[0]?.message.messageId).toBe("b");
    expect(tree[0]?.children[0]?.message.messageId).toBe("a");
  });

  it("reparents an orphan after another page supplies its parent", () => {
    const firstPage = [message("root"), message("child", "late-parent")];
    const merged = mergeMessages(firstPage, [message("late-parent", "root"), message("child")]);
    const tree = buildThreadTree(merged);

    expect(merged).toHaveLength(3);
    expect(tree[0]?.children[0]?.message.messageId).toBe("late-parent");
    expect(tree[0]?.children[0]?.children[0]?.message.messageId).toBe("child");
  });
});
