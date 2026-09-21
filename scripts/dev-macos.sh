#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
app_repo=${1:-"$repo/../ynotv"}
app_repo=$(CDPATH= cd -- "$app_repo" && pwd)

if [ ! -f "$app_repo/package.json" ] ||
   ! grep -q '"name": "ynotv"' "$app_repo/package.json"; then
  echo "not a ynoTV application checkout: $app_repo" >&2
  exit 1
fi

version=$(tr -d '[:space:]' < "$repo/VERSION")
echo "building $version incrementally from $repo"
YNOTV_NATIVE_INCREMENTAL=1 YNOTV_NATIVE_SKIP_ARCHIVE=1 \
  "$repo/scripts/build-macos.sh" "$version"

node "$app_repo/scripts/setup-native-runtime.mjs" --from "$repo/.work/stage"
echo "installed local Native DASH runtime into $app_repo"
echo "restart the application with: pnpm dev:clean"
