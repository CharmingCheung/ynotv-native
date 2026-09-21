param([string]$AppRepo = "")
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
if (-not $AppRepo) { $AppRepo = Join-Path (Split-Path -Parent $repo) "ynotv" }
$AppRepo = (Resolve-Path $AppRepo).Path
$msysBash = "C:\msys64\usr\bin\bash.exe"
if (-not (Test-Path $msysBash)) { throw "MSYS2 is required at C:\msys64" }

$version = (Get-Content (Join-Path $repo "VERSION") -Raw).Trim()
$env:YNOTV_PATH_TO_CONVERT = $repo
$repoMsys = (& $msysBash -lc 'cygpath -u "$YNOTV_PATH_TO_CONVERT"').Trim()
$env:YNOTV_NATIVE_REPO_MSYS = $repoMsys
$env:YNOTV_NATIVE_VERSION = $version
& $msysBash -lc 'YNOTV_NATIVE_INCREMENTAL=1 YNOTV_NATIVE_SKIP_ARCHIVE=1 "$YNOTV_NATIVE_REPO_MSYS/scripts/build-windows.sh" "$YNOTV_NATIVE_VERSION"'
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

node (Join-Path $AppRepo "scripts\setup-native-runtime.mjs") --from (Join-Path $repo ".work\windows\stage")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "installed local Native DASH runtime into $AppRepo"
Write-Host "restart the application with: pnpm dev:clean"
