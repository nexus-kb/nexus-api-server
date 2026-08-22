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

  const pad = (part: number) => String(part).padStart(2, "0");
  return [
    `${date.getUTCFullYear()}-${pad(date.getUTCMonth() + 1)}-${pad(date.getUTCDate())}`,
    `${pad(date.getUTCHours())}:${pad(date.getUTCMinutes())}`,
    "UTC",
  ].join(" ");
}

export function plural(count: number, singular: string, pluralForm = `${singular}s`): string {
  return `${count} ${count === 1 ? singular : pluralForm}`;
}
