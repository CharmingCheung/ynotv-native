# ynoTV native media runtime

Reproducible source and CI packaging for the patched `libmpv` used by ynoTV's
Native DASH player. Application code belongs in
[`CharmingCheung/ynotv-fork`](https://github.com/CharmingCheung/ynotv-fork);
this repository owns only the native patch, its regression fixtures, and the
versioned runtime artifacts consumed by `pnpm dev`.

## Pinned sources

- mpv: `cfd818bcaef262f82596f49444ee80073fa6d49a`
- libplacebo: `cee9b076f2c63104ccfd497fa79c39a867293ec4` (`v7.360.1`)
- packet ABI: current live/DVR stream `RDPKT006`; older revisions are retained
  only by regression fixtures

The macOS development artifact contains `libmpv.2.dylib`, its standard
`libmpv.dylib` linker symlink, and the exact pinned `libplacebo.360.dylib`.
Their mutual install names are rewritten relative to `@loader_path`, so
consumers do not need this repository or a temporary build tree. Other codec
libraries remain normal Homebrew development prerequisites; production DMG
relocation is deliberately handled separately.

## Build locally on Apple Silicon

```sh
brew install mpv meson ninja pkg-config
./scripts/build-macos.sh v0.1.0
```

Outputs are written to `dist/`:

- `ynotv-native-macos-arm64-v0.1.0.tar.gz`
- `ynotv-native-macos-arm64-v0.1.0.tar.gz.sha256`

The build validates the architecture, rejects temporary/build-machine paths,
checks the `RDPKT006` and `YNOIMSC1` feature markers, and runs mpv's Meson test
suite.

## Publish a release

Push a semantic version tag such as `v0.1.0`. GitHub Actions builds the same
artifact and attaches it and its checksum to that release. The ynoTV repository
pins both the tag and asset name; changing the native ABI requires a new tag and
an explicit consumer update.

```sh
git tag v0.1.0
git push origin master --tags
```

Do not replace an existing versioned release asset. Create a new tag instead.

## Patch maintenance

`apply-to-mpv.sh` refuses any mpv revision other than the pinned commit. The
patch adds the bounded packet demuxer, seek interrupt hook, runtime codec
generation, logical track metadata, and the TTML/IMSC subtitle bridges. Run the
fixture suites against the build tree when modifying the protocol:

```sh
./run-tests.sh .work/mpv-build/mpv .work/prefix/lib
./run-live-generation-tests.sh .work/mpv-build/mpv .work/prefix/lib .work/mpv
./run-track-switch-tests.sh .work/mpv-build/mpv .work/prefix/lib
```

The extended fixture suites expect the generated C1 media corpus beside this
checkout and are maintainer tests; the release workflow always runs mpv's 39
Meson tests plus ABI marker and install-name validation.

## License

ynoTV changes in this repository are licensed under AGPL-3.0. mpv and bundled
third-party libraries retain their upstream licenses; release artifacts include
a machine-readable build manifest and the repository license.
