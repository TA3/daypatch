#!/bin/bash
# Tests that need no copy of Dia (run in CI and locally).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
pass() { echo "ok   $1"; }

# 1. The patch and the companion compile without warnings.
clang -dynamiclib -arch arm64 -fobjc-arc -O2 -Wall -Werror -Wno-unused-function \
    -framework AppKit -framework QuartzCore -lsqlite3 -DDAYPATCH_VERSION="\"test\"" \
    -o "$WORK/daypatch.dylib" "$ROOT"/src/*.m
pass "daypatch.dylib builds"
swiftc -O -swift-version 5 -module-name DayPatch -target arm64-apple-macos14 -o "$WORK/DayPatch" "$ROOT"/companion/Sources/*.swift
pass "companion builds"

# 2. insert-dylib adds a weak load command and the binary still runs.
clang -O2 -o "$WORK/insert-dylib" "$ROOT/tools/insert-dylib.c"
printf '#include <stdio.h>\nint main(void){puts("hello");return 0;}\n' > "$WORK/hello.c"
clang -Wl,-headerpad,0x200 -o "$WORK/hello" "$WORK/hello.c"
codesign --remove-signature "$WORK/hello"
"$WORK/insert-dylib" "$WORK/hello" "@executable_path/missing.dylib" >/dev/null
"$WORK/insert-dylib" "$WORK/hello" "@executable_path/missing.dylib" | grep -q "already present"
codesign -f -s - "$WORK/hello"
otool -l "$WORK/hello" | grep -A2 LC_LOAD_WEAK_DYLIB | grep -q "@executable_path/missing.dylib"
[ "$("$WORK/hello")" = "hello" ]
pass "insert-dylib: weak load command added once, binary still launches"

# 3. Update signatures: sign, verify, and reject a tampered file.
PUB="$(swift "$ROOT/tools/update-key.swift" generate "$WORK/key")"
echo "payload" > "$WORK/file"
DAYPATCH_UPDATE_PRIVATE_KEY="$(cat "$WORK/key")" swift "$ROOT/tools/update-key.swift" sign "$WORK/file" > "$WORK/file.sig"
swift "$ROOT/tools/update-key.swift" verify "$WORK/file" "$WORK/file.sig" "$PUB" | grep -q OK
echo "tampered" > "$WORK/file"
if swift "$ROOT/tools/update-key.swift" verify "$WORK/file" "$WORK/file.sig" "$PUB" 2>/dev/null; then echo "FAIL tampered file verified"; exit 1; fi
pass "update signatures verify and reject tampering"

# 4. Nothing of Dia's is in the repository.
if find "$ROOT" -path "$ROOT/build" -prune -o \( -name '*.icns' -o -name '*.car' -o -name 'Dia.app' \) -print | grep -q .; then
    echo "FAIL Dia assets found in the repository"; exit 1
fi
pass "no Dia binaries or artwork in the repository"
