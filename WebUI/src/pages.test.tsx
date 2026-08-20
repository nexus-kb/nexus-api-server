import { HashRouter, Route } from "@solidjs/router";
import { cleanup, render, screen, waitFor, within } from "@solidjs/testing-library";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";
import { ThreadListPage } from "./pages/ThreadListPage";
import { ThreadPage } from "./pages/ThreadPage";
import type {
  MessageDetail,
  ThreadDetail,
  ThreadListResponse,
  ThreadMessagesResponse,
} from "./types";

const thread: ThreadDetail = {
  rootMessageId: "root/id?value#fragment%test@example.com",
  subject: "[PATCH] net: repair the packet path",
  author: "Kernel Developer <developer@example.com>",
  startedAt: "2026-08-15T12:00:00Z",
  lastActivityAt: "2026-08-15T13:00:00Z",
  messageCount: 3,
  missingMessageCount: 1,
  kind: "patch-series",
  mailingLists: [{ name: "Linux Kernel Mailing List", archiveGroup: "lkml" }],
  subsystems: [{ name: "Networking", mailingListAddress: "netdev@example.com" }],
  patchSeries: [
    {
      coverLetterMessageId: null,
      status: "pending",
      totalParts: 2,
      receivedParts: 2,
    },
  ],
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  window.location.hash = "";
});

describe("ThreadListPage", () => {
  it("filters by mailing list, resets the cursor, and paginates", async () => {
    window.location.hash = "#/?cursor=old-cursor";
    const firstPage: ThreadListResponse = {
      items: [thread],
      pagination: { previousCursor: "previous-cursor", nextCursor: "next-cursor" },
    };
    const fetchMock = vi.fn((input: RequestInfo | URL) => {
      const url = String(input);
      if (url === "/api/v1/mailing-lists") {
        return Promise.resolve(
          jsonResponse({
            items: [
              { name: "Linux Kernel Mailing List", archiveGroup: "lkml" },
              { name: "Netdev", archiveGroup: "netdev" },
            ],
          }),
        );
      }
      return Promise.resolve(jsonResponse(firstPage));
    });
    vi.stubGlobal("fetch", fetchMock);

    render(() => (
      <HashRouter preload={false}>
        <Route path="/" component={ThreadListPage} />
      </HashRouter>
    ));

    expect(await screen.findByText("[PATCH] net: repair the packet path")).toBeInTheDocument();
    expect(screen.queryByRole("heading", { name: "Threads" })).not.toBeInTheDocument();
    expect(screen.queryByText("Mailing list")).not.toBeInTheDocument();
    expect(screen.queryByText("1 thread")).not.toBeInTheDocument();
    expect(screen.getByText(/^created /)).toHaveAttribute("title");
    expect(screen.getByText(/^updated /)).toHaveAttribute("title");
    expect(within(screen.getByRole("list")).getByText("lkml")).toHaveAttribute(
      "title",
      "Linux Kernel Mailing List",
    );
    expect(screen.getByRole("option", { name: "lkml" })).toBeInTheDocument();
    await userEvent.selectOptions(screen.getByLabelText("Filter by mailing list"), "netdev");

    await waitFor(() => {
      expect(window.location.hash).toContain("mailingList=netdev");
      expect(window.location.hash).not.toContain("old-cursor");
    });

    await userEvent.click(screen.getByRole("button", { name: "Next" }));
    await waitFor(() => expect(window.location.hash).toContain("cursor=next-cursor"));

    const threadRequests = fetchMock.mock.calls
      .map(([input]) => String(input))
      .filter((url) => url.startsWith("/api/v1/threads?"));
    expect(threadRequests.some((url) => url.includes("mailingList=netdev"))).toBe(true);
  });
});

describe("ThreadPage", () => {
  it("loads the tree, expands and caches details, skips missing details, and appends pages", async () => {
    const rootMessage = {
      messageId: thread.rootMessageId,
      inReplyToMessageId: null,
      referenceMessageIds: [],
      availability: "available" as const,
      subject: thread.subject,
      author: thread.author,
      sentAt: thread.startedAt,
      bodyPreview: "Root message preview",
      patch: { partIndex: 0, totalParts: 2 },
    };
    const firstMessages: ThreadMessagesResponse = {
      rootMessageId: thread.rootMessageId,
      items: [
        rootMessage,
        {
          messageId: "missing@example.com",
          inReplyToMessageId: thread.rootMessageId,
          referenceMessageIds: [thread.rootMessageId],
          availability: "missing",
          subject: "Missing reply",
          author: null,
          sentAt: null,
          bodyPreview: null,
          patch: null,
        },
      ],
      pagination: { previousCursor: null, nextCursor: "more-messages" },
    };
    const secondMessages: ThreadMessagesResponse = {
      rootMessageId: thread.rootMessageId,
      items: [
        {
          messageId: "child@example.com",
          inReplyToMessageId: thread.rootMessageId,
          referenceMessageIds: [thread.rootMessageId],
          availability: "available",
          subject: "Re: repair the packet path",
          author: "Reviewer <reviewer@example.com>",
          sentAt: "2026-08-15T13:00:00Z",
          bodyPreview: "Reviewed-by: Reviewer",
          patch: null,
        },
      ],
      pagination: { previousCursor: "back", nextCursor: null },
    };
    const detail: MessageDetail = {
      ...rootMessage,
      rootMessageId: thread.rootMessageId,
      to: [{ name: "Netdev", email: "netdev@example.com" }],
      cc: [],
      body: "Full root message body",
      mailingLists: thread.mailingLists,
      subsystems: thread.subsystems,
      loreUrl: "https://lore.kernel.org/r/root",
    };
    const childDetail: MessageDetail = {
      ...detail,
      messageId: "child@example.com",
      inReplyToMessageId: thread.rootMessageId,
      referenceMessageIds: [thread.rootMessageId],
      subject: "Re: repair the packet path",
      author: "Reviewer <reviewer@example.com>",
      sentAt: "2026-08-15T13:00:00Z",
      body: "Reviewed-by: Reviewer",
      patch: null,
      loreUrl: "https://lore.kernel.org/r/child",
    };
    const fetchMock = vi.fn((input: RequestInfo | URL) => {
      const url = String(input);
      if (url.includes("/messages?")) {
        return Promise.resolve(
          jsonResponse(url.includes("cursor=more-messages") ? secondMessages : firstMessages),
        );
      }
      if (url.startsWith("/api/v1/messages/")) {
        return Promise.resolve(
          jsonResponse(url.includes("child%40example.com") ? childDetail : detail),
        );
      }
      if (url.startsWith("/api/v1/threads/")) {
        return Promise.resolve(jsonResponse(thread));
      }
      return Promise.resolve(jsonResponse({ reason: "Not found" }, 404));
    });
    vi.stubGlobal("fetch", fetchMock);
    window.location.hash = `#${new URL("https://nexus.test" + `/thread?${new URLSearchParams({ root: thread.rootMessageId })}`).pathname}${new URL("https://nexus.test" + `/thread?${new URLSearchParams({ root: thread.rootMessageId })}`).search}`;

    render(() => (
      <HashRouter preload={false}>
        <Route path="/thread" component={ThreadPage} />
      </HashRouter>
    ));

    expect(await screen.findByText("Full root message body")).toBeInTheDocument();
    expect(screen.queryByText("Root message preview")).not.toBeInTheDocument();
    expect(screen.queryByText("[message unavailable]", { exact: false })).not.toBeInTheDocument();
    expect(screen.queryByText("patch 0/2")).not.toBeInTheDocument();
    expect(
      fetchMock.mock.calls.some(([input]) => String(input).includes("missing%40example.com")),
    ).toBe(false);

    await userEvent.click(screen.getByRole("button", { name: /Collapse message from/ }));
    expect(screen.queryByText("Full root message body")).not.toBeInTheDocument();
    expect(screen.queryByText("Root message preview")).not.toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: /Expand message from/ }));
    expect(screen.getByText("Full root message body")).toBeInTheDocument();

    await userEvent.click(screen.getByRole("button", { name: "Load more messages" }));
    expect(await screen.findByText("Reviewed-by: Reviewer")).toBeInTheDocument();

    const detailRequests = fetchMock.mock.calls.filter(([input]) =>
      String(input).startsWith("/api/v1/messages/"),
    );
    expect(detailRequests).toHaveLength(2);
  });
});
