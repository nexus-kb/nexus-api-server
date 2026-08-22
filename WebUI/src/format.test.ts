import { describe, expect, it } from "vitest";
import { absoluteDate } from "./format";

describe("absoluteDate", () => {
  it("formats timestamps in UTC", () => {
    expect(absoluteDate("2026-08-15T08:30:00-04:00")).toBe(
      "2026-08-15 12:30 UTC",
    );
  });

  it("preserves invalid and missing values", () => {
    expect(absoluteDate("not-a-date")).toBe("not-a-date");
    expect(absoluteDate(null)).toBe("unknown date");
  });
});
