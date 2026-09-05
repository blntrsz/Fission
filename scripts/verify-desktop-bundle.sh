#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:?usage: verify-desktop-bundle.sh /path/to/Fission.app}"
EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$APP_PATH/Contents/Info.plist")"
EXECUTABLE_PATH="$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
EXECUTABLE_DIR="$(dirname "$EXECUTABLE_PATH")"

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
  echo "error: app executable is missing: $EXECUTABLE_PATH" >&2
  exit 1
fi

codesign --verify --deep --strict "$APP_PATH"
signature_info="$(codesign -dv --verbose=2 "$APP_PATH" 2>&1)"
if grep -q 'Signature=adhoc' <<< "$signature_info" && grep -q 'flags=.*runtime' <<< "$signature_info"; then
  echo "error: an ad-hoc signed app cannot use hardened runtime with embedded dynamic frameworks" >&2
  exit 1
fi

rpaths="$({
  otool -l "$EXECUTABLE_PATH" | awk '
    $1 == "cmd" && $2 == "LC_RPATH" { in_rpath = 1; next }
    in_rpath && $1 == "path" { print $2; in_rpath = 0 }
  '
} | sort -u)"

failure=0
while IFS= read -r dependency; do
  [[ -n "$dependency" ]] || continue
  relative_path="${dependency#@rpath/}"
  resolved=0

  while IFS= read -r rpath; do
    [[ -n "$rpath" ]] || continue
    candidate="${rpath//@executable_path/$EXECUTABLE_DIR}/$relative_path"
    candidate="${candidate//@loader_path/$EXECUTABLE_DIR}"
    if [[ -e "$candidate" ]]; then
      resolved=1
      break
    fi
  done <<< "$rpaths"

  if [[ "$resolved" -eq 0 ]]; then
    echo "error: $dependency is not reachable through the executable's LC_RPATH entries" >&2
    failure=1
  fi
done < <(otool -L "$EXECUTABLE_PATH" | awk '$1 ~ /^@rpath\// { print $1 }' | sort -u)

if [[ "$failure" -ne 0 ]]; then
  echo "LC_RPATH entries:" >&2
  if [[ -n "$rpaths" ]]; then
    printf '  %s\n' "$rpaths" >&2
  else
    echo "  (none)" >&2
  fi
  exit 1
fi

echo "Verified runtime dependencies for $APP_PATH"
