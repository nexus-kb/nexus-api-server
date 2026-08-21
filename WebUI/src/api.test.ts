import { afterEach, describe, expect, it, vi } from "vitest";
import {
  ApiError,
  encodeMessageID,
  getThreadPatchLineages,
  getThreads,
  threadListURL,
  threadRoute,
} from "./api";

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("API URL helpers", () => {
  it("round-trips message IDs through the client route", () => {
    const messageID = "message/path?query#fragment%value@example.com";
    const route = threadRoute(messageID);
    const query = new URLSearchParams(route.slice(route.indexOf("?") + 1));

    expect(route.startsWith("/thread?")).toBe(true);
    expect(query.get("root")).toBe(messageID);
    expect(encodeMessageID(messageID)).toBe(
      "message%2Fpath%3Fquery%23fragment%25value%40example.com",
    );
  });

  it("preserves the thread cursor and filter scope", () => {
    const url = new URL(
      threadListURL({
        mailingList: "linux-kernel",
        q: 'RCU author:"Paul McKenney"',
        cursor: "opaque+/=",
        limit: 25,
      }),
      "https://nexus.test",
    );

    expect(url.pathname).toBe("/api/v1/threads");
    expect(url.searchParams.get("limit")).toBe("25");
    expect(url.searchParams.get("mailingList")).toBe("linux-kernel");
    expect(url.searchParams.get("q")).toBe('RCU author:"Paul McKenney"');
    expect(url.searchParams.get("cursor")).toBe("opaque+/=");
  });

  it("surfaces Vapor error reasons", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        new Response(JSON.stringify({ error: true, reason: "Invalid pagination cursor" }), {
          status: 400,
          headers: { "Content-Type": "application/json" },
        }),
      ),
    );

    await expect(getThreads()).rejects.toEqual(
      new ApiError(400, "Invalid pagination cursor"),
    );
  });

  it("encodes thread IDs for lineage lookup", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ items: [] }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }),
    );
    vi.stubGlobal("fetch", fetchMock);

    await getThreadPatchLineages(
      "root/path@example.com"
    );

    expect(fetchMock).toHaveBeenCalledWith(
      "/api/v1/threads/root%2Fpath%40example.com/patch-lineages",
      expect.anything(),
    );
  });
});
