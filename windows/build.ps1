# Compila o SnapLens para Windows (x64, self-contained: não exige .NET instalado).
# Saída: windows\dist\SnapLens\SnapLens.exe e windows\dist\SnapLens-windows-x64.zip
# Com Inno Setup instalado (iscc no PATH), gera também windows\dist\SnapLens-Setup.exe.
param([string]$Version = "1.0.0")
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$dist = Join-Path $root "dist"
$out = Join-Path $dist "SnapLens"

$dotnet = (Get-Command dotnet -ErrorAction SilentlyContinue).Source
if (-not $dotnet) { $dotnet = Join-Path $env:LOCALAPPDATA "Microsoft\dotnet\dotnet.exe" }
if (-not (Test-Path $dotnet)) { throw "Instale o .NET 8 SDK: https://dotnet.microsoft.com/download/dotnet/8.0" }

$icon = Join-Path $root "SnapLens\Assets\SnapLens.ico"
if (-not (Test-Path $icon)) { python (Join-Path $root "..\Tools\make_icon_windows.py") $icon }

if (Test-Path $out) { Remove-Item -Recurse -Force $out }
& $dotnet publish (Join-Path $root "SnapLens\SnapLens.csproj") -c Release -r win-x64 --self-contained true `
    -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:EnableCompressionInSingleFile=true `
    -p:Version=$Version -o $out
if ($LASTEXITCODE -ne 0) { throw "dotnet publish falhou" }

$zip = Join-Path $dist "SnapLens-windows-x64.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $out "*") -DestinationPath $zip

$iscc = (Get-Command iscc -ErrorAction SilentlyContinue).Source
if (-not $iscc) { $iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" }
if (Test-Path $iscc) {
    & $iscc "/DAppVersion=$Version" (Join-Path $root "installer.iss")
    if ($LASTEXITCODE -ne 0) { throw "Inno Setup falhou" }
} else {
    Write-Host "(Inno Setup não encontrado: instalador não gerado; o .zip está pronto)"
}
Write-Host "OK -> $dist"
