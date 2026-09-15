const unsafeCharacterPattern = /\p{Cc}|\p{Cf}|\p{Zl}|\p{Zp}/u;

export function handlerDescription(applicationName: string | null): string {
  return applicationName ? `“${applicationName}”` : "the default application";
}

export function displayString(rawValue: string): string {
  let normalized: string;
  const prepared = percentEncodeASCIIControls(rawValue);
  try {
    const url = new URL(prepared);
    if (url.protocol === "file:") {
      normalized = posixNormalize(decodeURIComponent(url.pathname));
    } else {
      normalized = url.href;
    }
  } catch {
    if (rawValue.startsWith("/") || rawValue.startsWith("~")) {
      normalized = posixNormalize(rawValue.replace(/^~/, ""));
    } else {
      normalized = prepared;
    }
  }

  let result = "";
  for (const character of normalized) {
    if (unsafeCharacterPattern.test(character)) {
      const hex = character.codePointAt(0)?.toString(16).toUpperCase() ?? "0";
      result += `\\u{${hex}}`;
    } else {
      result += character;
    }
  }
  return result;
}

export function percentEncodeASCIIControls(value: string): string {
  return [...value]
    .map((character) => {
      const code = character.codePointAt(0) ?? 0;
      if (code < 0x20 || code === 0x7f) {
        return `%${code.toString(16).padStart(2, "0").toUpperCase()}`;
      }
      return character;
    })
    .join("");
}

export function posixNormalize(path: string): string {
  const absolute = path.startsWith("/");
  const parts = path.split("/");
  const out: string[] = [];
  for (const part of parts) {
    if (part === "" || part === ".") {
      continue;
    }
    if (part === "..") {
      out.pop();
      continue;
    }
    out.push(part);
  }
  const joined = out.join("/");
  return absolute ? `/${joined}` : joined;
}
