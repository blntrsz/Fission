export function title(forNumber: number): string {
  return `Tab ${forNumber}`;
}

export function nextNumber(existingTitles: Iterable<string>): number {
  const used = new Set<number>();
  for (const existing of existingTitles) {
    const parsed = numberIn(existing);
    if (parsed != null) {
      used.add(parsed);
    }
  }
  let candidate = 1;
  while (used.has(candidate)) {
    candidate += 1;
  }
  return candidate;
}

export function numberIn(titleText: string): number | null {
  const prefix = "Tab ";
  if (!titleText.startsWith(prefix)) {
    return null;
  }
  const suffix = titleText.slice(prefix.length);
  const parsed = Number.parseInt(suffix, 10);
  if (!Number.isInteger(parsed) || parsed <= 0 || String(parsed) !== suffix) {
    return null;
  }
  return parsed;
}
