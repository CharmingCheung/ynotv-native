#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
version=${1:-dev}
incremental=${YNOTV_NATIVE_INCREMENTAL:-0}
skip_archive=${YNOTV_NATIVE_SKIP_ARCHIVE:-0}
mpv_commit=e76a35ec95b27f5cf2d27b043b5e2e0d90e468ae

case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) ;; *) echo "build-windows.sh requires MSYS2 on Windows" >&2; exit 1;; esac
for command in git meson ninja pkg-config cc llvm-dlltool gendef ldd 7z; do
  command -v "$command" >/dev/null 2>&1 || { echo "missing build tool: $command" >&2; exit 1; }
done
work="$repo/.work/windows"
dist="$repo/dist"
mpv_build="$work/mpv-build"
stage="$work/stage"
patch_stamp="$work/applied-patch.sha256"
asset="ynotv-native-windows-x64-$version.zip"
mkdir -p "$work" "$dist"

if [ ! -d "$work/mpv/.git" ]; then
  mkdir -p "$work/mpv"
  git -C "$work/mpv" init
  git -C "$work/mpv" remote add origin https://github.com/mpv-player/mpv.git
fi
patch_digest=$(sha256sum "$repo/apply-to-mpv.sh" "$repo"/mpv-patch/* | sha256sum | awk '{print $1}')
applied_digest=$(cat "$patch_stamp" 2>/dev/null || true)
current_commit=$(git -C "$work/mpv" rev-parse HEAD 2>/dev/null || true)
if [ "$incremental" = 1 ] && [ "$patch_digest" = "$applied_digest" ] &&
   [ "$current_commit" = "$mpv_commit" ] && [ -f "$work/mpv/demux/demux_rustdash.c" ]; then
  echo "reusing unchanged patched mpv checkout"
else
  git -C "$work/mpv" fetch --depth 1 origin "$mpv_commit"
  git -C "$work/mpv" reset --hard
  git -C "$work/mpv" clean -fd
  git -C "$work/mpv" checkout --detach "$mpv_commit"
  "$repo/apply-to-mpv.sh" "$work/mpv"
  printf '%s\n' "$patch_digest" > "$patch_stamp"
fi

setup_args=("$mpv_build" "$work/mpv" -Dbuild-date=false -Dcplayer=true -Dlibmpv=true
  -Dtests=true -Dgl=enabled -Dvulkan=enabled -Djavascript=disabled -Dlua=disabled)
if [ "$incremental" = 1 ] && [ -f "$mpv_build/build.ninja" ]; then
  meson setup "${setup_args[@]}" --reconfigure
else
  meson setup "${setup_args[@]}" --wipe
fi
meson compile -C "$mpv_build"
# The MSYS2 FFmpeg dependency pulls in GGML. Repeated DLL load/unload in
# mpv's lifetime test trips GGML's process-global terminate-handler guard on
# Windows runners; the runtime and all other mpv tests remain covered.
meson test -C "$mpv_build" --print-errorlogs --exclude libmpv-lifetime

producer_dir="$repo/packet-producer"
cc -std=c11 -O2 -Wall -Wextra -Wpedantic -Werror \
  $(pkg-config --cflags libavformat libavcodec libavutil openssl) \
  "$producer_dir/cenc_transform.c" "$producer_dir/cenc_component_producer.c" \
  -o "$work/cenc_component_producer.exe" \
  $(pkg-config --libs libavformat libavcodec libavutil openssl)

rm -rf "$stage"
mkdir -p "$stage"
mpv_dll=$(find "$mpv_build" -type f -name 'libmpv-2.dll' -print -quit)
[ -n "$mpv_dll" ] || { echo "libmpv-2.dll was not built" >&2; exit 1; }
cp "$mpv_dll" "$stage/libmpv-2.dll"
cp "$work/cenc_component_producer.exe" "$stage/cenc_component_producer.exe"
(cd "$stage" && gendef libmpv-2.dll >/dev/null)
llvm-dlltool -m i386:x86-64 -d "$stage/libmpv-2.def" -l "$stage/mpv.lib" -D libmpv-2.dll
rm -f "$stage/libmpv-2.def"

# Bundle the complete non-system DLL closure for libmpv and the producer.
copy_deps() {
  local current dep base
  local -a queue=("$stage/libmpv-2.dll" "$stage/cenc_component_producer.exe")
  local index=0
  while [ $index -lt ${#queue[@]} ]; do
    current=${queue[$index]}; index=$((index + 1))
    while IFS= read -r dep; do
      [ -f "$dep" ] || continue
      base=$(basename "$dep")
      [ -f "$stage/$base" ] && continue
      cp "$dep" "$stage/$base"
      queue+=("$stage/$base")
    done < <(ldd "$current" 2>/dev/null | awk '/=> \/(ucrt64|mingw64)\// {print $3}')
  done
}
copy_deps

grep -a -q RDPKT006 "$stage/libmpv-2.dll"
grep -a -q YNOIMSC1 "$stage/libmpv-2.dll"
producer_digest=$(sha256sum "$producer_dir"/* "$repo/rustdash_packet_abi.h" | sha256sum | awk '{print $1}')
cat > "$stage/manifest.json" <<EOF
{
  "schema": 1,
  "version": "$version",
  "platform": "windows-x64",
  "mpvCommit": "$mpv_commit",
  "producerSourceSha256": "$producer_digest",
  "packetAbi": "RDPKT006",
  "subtitleBitmapAbi": "YNOIMSC1",
  "runtime": "ucrt64"
}
EOF
cp "$repo/LICENSE" "$stage/LICENSE-ynotv"

if [ "$skip_archive" != 1 ]; then
  rm -f "$dist/$asset" "$dist/$asset.sha256"
  (cd "$stage" && 7z a -tzip "$dist/$asset" . >/dev/null)
  sha256sum "$dist/$asset" > "$dist/$asset.sha256"
  echo "created $dist/$asset"
fi
