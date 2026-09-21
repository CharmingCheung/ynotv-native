#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: $0 /path/to/mpv-e76a35ec-checkout" >&2
  exit 2
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
mpv_src=$1
expected=e76a35ec95b27f5cf2d27b043b5e2e0d90e468ae
actual=$(git -C "$mpv_src" rev-parse HEAD)
if [ "$actual" != "$expected" ]; then
  echo "expected mpv $expected, got $actual" >&2
  exit 1
fi
if [ -e "$mpv_src/demux/demux_rustdash.c" ]; then
  echo "demux/demux_rustdash.c already exists" >&2
  exit 1
fi

cp "$script_dir/mpv-patch/demux_rustdash.c" "$mpv_src/demux/demux_rustdash.c"
cp "$script_dir/mpv-patch/rdp_endian.h" "$mpv_src/demux/rdp_endian.h"
git -C "$mpv_src" apply "$script_dir/mpv-patch/register.patch"
git -C "$mpv_src" apply --unidiff-zero "$script_dir/mpv-patch/ttml-ass-bridge.patch"
git -C "$mpv_src" apply "$script_dir/mpv-patch/ttml-bitmap-bridge.patch"
git -C "$mpv_src" diff --check
echo "experimental mpv adapter applied to $mpv_src"
