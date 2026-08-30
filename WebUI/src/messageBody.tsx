import { For, createMemo } from "solid-js";
import { DiffStat, DiffViewer } from "./diffViewer";

export type MessageBodySegment =
  | { kind: "text"; text: string }
  | { kind: "diffstat"; text: string }
  | { kind: "diff"; text: string };

interface BodyLine {
  text: string;
  start: number;
  end: number;
}

interface BodyRange {
  kind: "diffstat" | "diff";
  start: number;
  end: number;
}

function splitBodyLines(body: string): BodyLine[] {
  const lines: BodyLine[] = [];
  let start = 0;

  while (start < body.length) {
    const newline = body.indexOf("\n", start);
    const end = newline === -1 ? body.length : newline + 1;
    const contentEnd = newline === -1 ? end : newline;
    let text = body.slice(start, contentEnd);

    if (text.endsWith("\r")) {
      text = text.slice(0, -1);
    }

    lines.push({ text, start, end });
    start = end;
  }

  return lines;
}

function isDiffstatSummary(line: string): boolean {
  return /^\s*\d+\s+files? changed(?:,\s+\d+\s+insertions?\(\+\))?(?:,\s+\d+\s+deletions?\(-\))?\s*$/.test(
    line,
  );
}

function isDiffstatRow(line: string): boolean {
  return /^\s*\S.*\s+\|\s+(?:\d+\s*[+\-.]*|Bin\s+.+)\s*$/.test(line);
}

function isPatchFooter(lines: readonly BodyLine[], index: number): boolean {
  const line = lines[index];
  const next = lines[index + 1];

  return (
    line?.text === "-- " &&
    next !== undefined &&
    /^\d+\.\d+(?:\.\d+)?(?:\s|$)/.test(next.text)
  );
}

export function parseMessageBody(body: string): MessageBodySegment[] {
  if (body.length === 0) {
    return [{ kind: "text", text: "" }];
  }

  const lines = splitBodyLines(body);
  const ranges: BodyRange[] = [];
  const firstDiffLine = lines.findIndex((line) => /^diff --git a\/.+ b\/.+$/.test(line.text));

  if (firstDiffLine !== -1) {
    let end = body.length;

    for (let index = firstDiffLine + 1; index < lines.length; index += 1) {
      if (isPatchFooter(lines, index)) {
        end = lines[index]?.start ?? end;
        break;
      }
    }

    ranges.push({
      kind: "diff",
      start: lines[firstDiffLine]?.start ?? 0,
      end,
    });
  }

  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    if (!line || !isDiffstatSummary(line.text)) {
      continue;
    }

    let firstRow = index;

    while (firstRow > 0) {
      const previous = lines[firstRow - 1];
      if (!previous || !isDiffstatRow(previous.text)) {
        break;
      }
      firstRow -= 1;
    }

    if (firstRow === index) {
      continue;
    }

    const start = lines[firstRow]?.start;
    if (start === undefined) {
      continue;
    }

    const overlapsDiff = ranges.some(
      (range) => start < range.end && line.end > range.start,
    );

    if (!overlapsDiff) {
      ranges.push({ kind: "diffstat", start, end: line.end });
    }
  }

  ranges.sort((left, right) => left.start - right.start);

  const segments: MessageBodySegment[] = [];
  let cursor = 0;

  for (const range of ranges) {
    if (range.start > cursor) {
      segments.push({ kind: "text", text: body.slice(cursor, range.start) });
    }

    segments.push({ kind: range.kind, text: body.slice(range.start, range.end) });
    cursor = range.end;
  }

  if (cursor < body.length) {
    segments.push({ kind: "text", text: body.slice(cursor) });
  }

  return segments;
}

function Segment(props: { segment: MessageBodySegment }) {
  switch (props.segment.kind) {
    case "text":
      return (
        <pre class="message-body-segment message-body-text">
          {props.segment.text}
        </pre>
      );

    case "diffstat":
      return <DiffStat text={props.segment.text} />;

    case "diff":
      return <DiffViewer diff={props.segment.text} />;
  }
}

export function MessageBody(props: { body: string }) {
  const segments = createMemo(() => parseMessageBody(props.body));

  return (
    <div class="message-body">
      <For each={segments()}>{(segment) => <Segment segment={segment} />}</For>
    </div>
  );
}
