#!/bin/bash
# One-time setup for signed DayPatch updates.
#  - Generates an ed25519 key pair.
#  - Writes the public key to companion/update-public-key.txt (commit this; it's built into DayPatch).
#  - Keeps the private key outside the repo, and prints how to store it as a GitHub secret
#    so the release workflow can sign DayPatch.zip.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEY_DIR="$HOME/.config/daypatch"
PRIVATE="$KEY_DIR/update-private-key"
PUBLIC="$ROOT/companion/update-public-key.txt"

mkdir -p "$KEY_DIR"
chmod 700 "$KEY_DIR"
swift "$ROOT/tools/update-key.swift" generate "$PRIVATE" > "$PUBLIC"

echo "Public key:  $PUBLIC (commit it)"
echo "Private key: $PRIVATE (keep it secret; back it up somewhere safe)"
echo
echo "Store the private key for GitHub Actions:"
echo "  gh secret set DAYPATCH_UPDATE_PRIVATE_KEY --repo TA3/daypatch < \"$PRIVATE\""
