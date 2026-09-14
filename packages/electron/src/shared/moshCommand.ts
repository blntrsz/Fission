const ALLOWED = /^[A-Za-z0-9\-._:@+]+$/;

export function posixQuote(value: string): string {
  if (value.length === 0) {
    return "''";
  }
  if (ALLOWED.test(value)) {
    return value;
  }
  return `'${value.replaceAll("'", `'\\''`)}'`;
}

export function normalizedDirectory(path: string | null | undefined): string | null {
  if (path == null) {
    return null;
  }
  let trimmed = path.trim();
  if (trimmed.length === 0) {
    return null;
  }
  while (trimmed.length > 1 && trimmed.endsWith("/")) {
    trimmed = trimmed.slice(0, -1);
  }
  return trimmed;
}

export function remoteDirectoryExpression(path: string): string {
  if (path === "~") {
    return `"$HOME"`;
  }
  if (path.startsWith("~/")) {
    return `"$HOME/${escapeDoubleQuoted(path.slice(2))}"`;
  }
  return `"${escapeDoubleQuoted(path)}"`;
}

export function loginShellCommand(
  target: string,
  sshPort: number | null | undefined,
  remoteDirectory?: string | null
): string {
  const arguments_: string[] = ["exec", "mosh"];
  if (sshPort != null && sshPort !== 22) {
    arguments_.push(`--ssh=${posixQuote(`ssh -p ${sshPort}`)}`);
  }
  arguments_.push(posixQuote(target));
  const directory = normalizedDirectory(remoteDirectory ?? null);
  if (directory) {
    arguments_.push("--", "sh", "-lc");
    arguments_.push(
      posixQuote(`cd -- ${remoteDirectoryExpression(directory)} && exec "\${SHELL:-/bin/sh}" -l`)
    );
  }
  return arguments_.join(" ");
}

function escapeDoubleQuoted(value: string): string {
  return value
    .replaceAll("\\", "\\\\")
    .replaceAll("\"", "\\\"")
    .replaceAll("$", "\\$")
    .replaceAll("`", "\\`");
}
