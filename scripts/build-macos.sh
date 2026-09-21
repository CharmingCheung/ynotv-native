#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
version=${1:-dev}
mpv_commit=cfd818bcaef262f82596f49444ee80073fa6d49a
libplacebo_commit=cee9b076f2c63104ccfd497fa79c39a867293ec4

if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != arm64 ]; then
  echo "build-macos.sh requires Apple Silicon macOS" >&2
  exit 1
fi
for command in git meson ninja pkg-config install_name_tool codesign; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "missing build tool: $command" >&2
    exit 1
  }
done

work="$repo/.work"
dist="$repo/dist"
prefix="$work/prefix"
mpv_build="$work/mpv-build"
stage="$work/stage"
asset="ynotv-native-macos-arm64-$version.tar.gz"

mkdir -p "$work" "$dist"

if [ ! -d "$work/libplacebo/.git" ]; then
  mkdir -p "$work/libplacebo"
  git -C "$work/libplacebo" init
  git -C "$work/libplacebo" remote add origin https://github.com/haasn/libplacebo.git
fi
git -C "$work/libplacebo" fetch --depth 1 origin "$libplacebo_commit"
git -C "$work/libplacebo" checkout --detach "$libplacebo_commit"
git -C "$work/libplacebo" submodule update --init --recursive --depth 1

meson setup "$work/libplacebo-build" "$work/libplacebo" --wipe \
  --prefix "$prefix" --libdir lib -Ddefault_library=shared \
  -Ddemos=false -Dtests=false -Dvulkan=enabled -Dopengl=enabled \
  -Dlcms=disabled
meson compile -C "$work/libplacebo-build"
meson install -C "$work/libplacebo-build"

if [ ! -d "$work/mpv/.git" ]; then
  mkdir -p "$work/mpv"
  git -C "$work/mpv" init
  git -C "$work/mpv" remote add origin https://github.com/mpv-player/mpv.git
fi
git -C "$work/mpv" fetch --depth 1 origin "$mpv_commit"
git -C "$work/mpv" reset --hard
git -C "$work/mpv" clean -fd
git -C "$work/mpv" checkout --detach "$mpv_commit"
"$repo/apply-to-mpv.sh" "$work/mpv"

export PKG_CONFIG_PATH="$prefix/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export DYLD_LIBRARY_PATH="$prefix/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
meson setup "$mpv_build" "$work/mpv" --wipe \
  -Dbuild-date=false -Dcplayer=true -Dlibmpv=true -Dtests=true \
  -Dgl=enabled -Dvulkan=auto -Djavascript=disabled -Dlua=disabled
meson compile -C "$mpv_build"
meson test -C "$mpv_build" --print-errorlogs

rm -rf "$stage"
mkdir -p "$stage"
cp "$mpv_build/libmpv.2.dylib" "$stage/libmpv.2.dylib"
cp "$prefix/lib/libplacebo.360.dylib" "$stage/libplacebo.360.dylib"
placebo_link=$(otool -L "$stage/libmpv.2.dylib" | awk '/libplacebo\.360\.dylib/{print $1; exit}')
if [ -z "$placebo_link" ]; then
  echo "libmpv does not link the pinned libplacebo" >&2
  exit 1
fi
install_name_tool -change "$placebo_link" @loader_path/libplacebo.360.dylib \
  "$stage/libmpv.2.dylib"
install_name_tool -id @loader_path/libplacebo.360.dylib "$stage/libplacebo.360.dylib"
codesign --force --sign - "$stage/libplacebo.360.dylib"
codesign --force --sign - "$stage/libmpv.2.dylib"
ln -s libmpv.2.dylib "$stage/libmpv.dylib"

strings "$stage/libmpv.2.dylib" | grep -q RDPKT006
strings "$stage/libmpv.2.dylib" | grep -q YNOIMSC1

find "$stage" -type f -name '*.dylib' -print | while IFS= read -r dylib; do
  if otool -L "$dylib" | tail -n +2 | grep -E '/(private/tmp|tmp/|var/folders|Users/[^/]+/)' >/dev/null; then
    echo "build-machine dependency in $dylib" >&2
    otool -L "$dylib" >&2
    exit 1
  fi
done

cat > "$stage/manifest.json" <<EOF
{
  "schema": 1,
  "version": "$version",
  "platform": "macos-arm64",
  "mpvCommit": "$mpv_commit",
  "libplaceboCommit": "$libplacebo_commit",
  "packetAbi": "RDPKT006",
  "subtitleBitmapAbi": "YNOIMSC1",
  "requiresHomebrew": true
}
EOF
cp "$repo/LICENSE" "$stage/LICENSE-ynotv"

tar -czf "$dist/$asset" -C "$stage" .
shasum -a 256 "$dist/$asset" > "$dist/$asset.sha256"
echo "created $dist/$asset"
