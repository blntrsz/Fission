const FORBIDDEN = /[ ~^:?*[\\]|[\u0000-\u001f\u007f]/;

export function normalized(raw: string | null | undefined): string | null {
  const trimmed = raw?.trim() ?? "";
  return trimmed.length === 0 ? null : trimmed;
}

export function isValid(name: string): boolean {
  if (name.length === 0 || name === "@") {
    return false;
  }
  if (name.startsWith("/") || name.endsWith("/") || name.startsWith("-")) {
    return false;
  }
  if (name.includes("..") || name.includes("//") || name.includes("@{")) {
    return false;
  }
  if (FORBIDDEN.test(name)) {
    return false;
  }
  return name.split("/").every((component) => {
    return (
      component.length > 0 &&
      !component.startsWith(".") &&
      !component.endsWith(".") &&
      !component.endsWith(".lock")
    );
  });
}
