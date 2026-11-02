# Compila o SnapLens para Windows (x64, self-contained: não exige .NET instalado).
# Saída: windows\dist\SnapLens\SnapLens.exe e windows\dist\SnapLens-windows-x64.zip
# Com Inno Setup instalado (iscc no PATH), gera também windows\dist\SnapLens-Setup.exe.
# Versão: arquivo VERSION na raiz (suba a cada release); build = nº de commits (sobe sozinho).
param([string]$Version = "", [string]$Build = "")
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
if (-not $Version) { $Version = (Get-Content (Join-Path $root "..\VERSION") -Raw).Trim() }
if (-not $Build) { $Build = (git -C $root rev-list --count HEAD 2>$null); if (-not $Build) { $Build = "1" } }

# Credenciais OAuth do OneDrive / Google Drive (opcional): .secrets\cloud.env com linhas CHAVE=valor
# (ONEDRIVE_CLIENT_ID, GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET). O csproj lê essas variáveis de ambiente.
$cloudEnv = Join-Path $root "..\.secrets\cloud.env"
if (Test-Path $cloudEnv) {
    foreach ($line in Get-Content $cloudEnv) {
        if ($line -match '^\s*([A-Z_]+)\s*=\s*(.*?)\s*$') {
            [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2].Trim('"'), "Process")
        }
    }
}
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
    -p:Version=$Version -p:FileVersion="$Version.$Build" -p:InformationalVersion="$Version ($Build)" -o $out
if ($LASTEXITCODE -ne 0) { throw "dotnet publish falhou" }

$zip = Join-Path $dist "SnapLens-windows-x64.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $out "*") -DestinationPath $zip

$iscc = (Get-Command iscc -ErrorAction SilentlyContinue).Source
if (-not $iscc) {
    $iscc = @("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe") |
        Where-Object { Test-Path $_ } | Select-Object -First 1
}
if ($iscc -and (Test-Path $iscc)) {
    & $iscc "/DAppVersion=$Version" (Join-Path $root "installer.iss")
    if ($LASTEXITCODE -ne 0) { throw "Inno Setup falhou" }
} else {
    Write-Host "(Inno Setup não encontrado: instalador não gerado; o .zip está pronto)"
}
Write-Host "OK -> $dist"
