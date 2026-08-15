export function displaySubject(subject: string | null): string {
  return subject?.trim() || "(no subject)";
}

export function displayAuthor(author: string | null): string {
  return author?.trim() || "unknown author";
}

export function absoluteDate(value: string | null): string {
  if (!value) {
    return "unknown date";
  }

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return value;
  }

  return new Intl.DateTimeFormat(undefined, {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(date);
}

export function relativeDate(value: string | null, now = Date.now()): string {
  if (!value) {
    return "unknown time";
  }

  const time = new Date(value).getTime();
  if (Number.isNaN(time)) {
    return value;
  }

  const seconds = Math.round((time - now) / 1_000);
  const intervals: Array<[Intl.RelativeTimeFormatUnit, number]> = [
    ["year", 31_536_000],
    ["month", 2_592_000],
    ["week", 604_800],
    ["day", 86_400],
    ["hour", 3_600],
    ["minute", 60],
  ];
  const formatter = new Intl.RelativeTimeFormat(undefined, { numeric: "auto" });

  for (const [unit, interval] of intervals) {
    if (Math.abs(seconds) >= interval) {
      return formatter.format(Math.round(seconds / interval), unit);
    }
  }

  return formatter.format(seconds, "second");
}

export function plural(count: number, singular: string, pluralForm = `${singular}s`): string {
  return `${count} ${count === 1 ? singular : pluralForm}`;
}
