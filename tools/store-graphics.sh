#!/usr/bin/env bash
# Regenerates the pictures the Play Store listing needs into docs/store:
# the 512x512 icon, the 1024x500 feature graphic and four phone screenshots
# per language. Run it before filling in or refreshing the store listing.
set -euo pipefail

cd "$(dirname "$0")/.."
out="$PWD/docs/store"
mkdir -p "$out"

STORE_GRAPHICS_DIR="$out" flutter test test/store/store_graphics_test.dart

echo
echo "Written to docs/store:"
ls -1 "$out"
