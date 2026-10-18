param(
    [Parameter(Mandatory=$true)][string] $ReleaseTag,
    [ValidateSet('x64','ARM64')][string] $Architecture = 'x64'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($ReleaseTag -cnotmatch '^v\d+\.\d+\.\d+$') { throw 'Use an official stable tag such as v1.18.8' }
$repo = (Resolve-Path '.').Path
$version = $ReleaseTag.Substring(1)
$name = "Sandboxie-Plus-$Architecture-$ReleaseTag.exe"
$api = "https://api.github.com/repos/sandboxie-plus/Sandboxie/releases/tags/$ReleaseTag"
$headers = @{ 'Accept' = 'application/vnd.github+json'; 'User-Agent'='SandboxiePlusPortableBuilder' }
Write-Host "Checking official Sandboxie Plus release $ReleaseTag..."
$release = Invoke-RestMethod -Uri $api -Headers $headers
if ($release.draft -or $release.prerelease -or $release.tag_name -cne $ReleaseTag) {
    throw 'Release is draft, prerelease or does not match selected tag'
}
$asset = @($release.assets | Where-Object { $_.name -ceq $name })
if ($asset.Count -ne 1) { throw "Official Windows installer '$name' not found in release" }
$installer = Join-Path $env:RUNNER_TEMP $name
Write-Host 'Downloading original developer-supplied installer...'
Invoke-WebRequest -Uri $asset[0].browser_download_url -OutFile $installer -Headers $headers
$actual = (Get-FileHash -Path $installer -Algorithm SHA256).Hash.ToLowerInvariant()
$validated = $false
if ($asset[0].digest -and $asset[0].digest -match '^sha256:([a-fA-F0-9]{64})$') {
    $expected = $Matches[1].ToLowerInvariant()
    if ($actual -ne $expected) { throw 'Release asset SHA-256 mismatch: refusing to package' }
    $validated = $true
    Write-Host 'Installer SHA-256 confirmed against official GitHub Release asset digest.'
}
# Fallback to independent developer-published sha256-checksums.txt
$shaAsset = @($release.assets | Where-Object { $_.name -ceq 'sha256-checksums.txt' })
if ($shaAsset.Count -eq 1) {
    $shaFile = Join-Path $env:RUNNER_TEMP 'sandboxie-release-sha256.txt'
    Invoke-WebRequest -Uri $shaAsset[0].browser_download_url -OutFile $shaFile -Headers $headers
    $entry = @(Get-Content $shaFile | Where-Object { $_ -match [regex]::Escape($name) + '\s*$' })
    if ($entry.Count -ne 1 -or $entry[0] -notmatch '^([a-fA-F0-9]{64})\s+\*?(.+)$') { throw 'Checksum entry missing or malformed' }
    if ($Matches[2] -cne $name -or $Matches[1].ToLowerInvariant() -ne $actual) { throw 'Official checksums.txt SHA-256 mismatch' }
    $validated = $true
    Write-Host 'Installer SHA-256 also confirmed against publisher checksum list.'
}
if (-not $validated) { throw 'No verifiable official SHA-256 value available; refusing to build' }

$stage = Join-Path $repo 'staging\SandboxiePlusPortable'
$app = Join-Path $stage 'App\SandboxiePlus'
$data = Join-Path $stage 'Data'
$settings = Join-Path $data 'Settings'
$out = Join-Path $repo 'artifacts'
if (Test-Path (Join-Path $repo 'staging')) { Remove-Item -Recurse -Force (Join-Path $repo 'staging') }
New-Item -ItemType Directory -Force $app,$settings,(Join-Path $data 'Sandboxes'),(Join-Path $data 'Logs'),(Join-Path $stage 'App\AppInfo'),(Join-Path $stage 'Other'),$out | Out-Null

# Inno Setup flags are validated against the official Sandboxie installer source.
# /PORTABLE=1 keeps driver/service installation from running on the GitHub runner.
# /OPEN_AGENT=0 prevents starting the UI, even if upstream defaults change.
$log = Join-Path $env:RUNNER_TEMP 'sandboxie-portable-extract.log'
$installArgs = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CURRENTUSER /PORTABLE=1 /OPEN_AGENT=0 /DIR="' + $app + '" /LOG="' + $log + '"'
Write-Host 'Extracting using official portable-mode installer (no kernel driver installation)...'
$p = Start-Process -FilePath $installer -ArgumentList $installArgs -PassThru -Wait
if ($p.ExitCode -ne 0) {
    if (Test-Path $log) { Get-Content $log -Tail 100 }
    throw "Official portable extraction failed (exit code $($p.ExitCode))"
}
foreach ($required in @('SandMan.exe','SbieDrv.sys','SbieSvc.exe','KmdUtil.exe','Sandboxie.ini','Sandboxie-Plus.ini')) {
    if (-not (Test-Path (Join-Path $app $required))) { throw "Extracted release missing: $required" }
}
# Defense-in-depth: packaging must never install the service on the runner.
foreach ($name in @('SbieDrv','SbieSvc')) {
    if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\$name") {
        throw "Unexpected Sandboxie service/driver registered on build runner: $name"
    }
}
foreach ($ini in @('Sandboxie.ini','Sandboxie-Plus.ini')) {
    Move-Item -Path (Join-Path $app $ini) -Destination (Join-Path $settings $ini)
}

# Original multi-resolution icon, pinned to this same official tag.
$iconUrl = "https://raw.githubusercontent.com/sandboxie-plus/Sandboxie/$ReleaseTag/Installer/SandManInstall.ico"
$icon = Join-Path $stage 'App\AppInfo\appicon.ico'
Invoke-WebRequest -Uri $iconUrl -OutFile $icon -Headers $headers
$bytes = [System.IO.File]::ReadAllBytes($icon)
if ($bytes.Length -lt 500 -or $bytes[0] -ne 0 -or $bytes[1] -ne 0 -or $bytes[2] -ne 1 -or $bytes[3] -ne 0) {
    throw 'Official .ico file invalid; not falling back to generic icon'
}
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
# PortableApps.com Menu requires metadata and PNG icons in addition to appicon.ico.
# This is menu metadata only; it does not install a driver or change sandbox settings.
$appInfo = Join-Path $stage 'App\AppInfo\appinfo.ini'
@"
[Format]
Type=PortableApps.comFormat
Version=3.9

[Details]
Name=Sandboxie Plus Portable
AppID=SandboxiePlusPortable-Community
Publisher=Sandboxie Plus Contributors (Community Package)
Homepage=https://github.com/sandboxie-plus/sandboxie
Category=Security
Description=Community portable package of Sandboxie Plus
Language=Multilingual

[License]
Shareable=true
OpenSource=true
Freeware=true
CommercialUse=true

[Version]
PackageVersion=$version.0
DisplayVersion=$version

[Dependencies]
RequiresAdmin=yes

[Control]
Icons=1
Start=SandboxiePlusPortable.exe
"@ | Set-Content -Path $appInfo -Encoding ASCII

# PNG icons are used by PortableApps.com Menu. Derive them from the official
# multi-resolution Sandboxie icon already pinned to the selected upstream tag.
Add-Type -AssemblyName System.Drawing
foreach ($size in @(16,32,75,128,256)) {
    $ico = [System.Drawing.Icon]::new($icon, [int]$size, [int]$size)
    try {
        $sourceBitmap = $ico.ToBitmap()
        try {
            $bitmap = [System.Drawing.Bitmap]::new([int]$size,[int]$size)
            try {
                $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
                try {
                    $graphics.Clear([System.Drawing.Color]::Transparent)
                    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                    $graphics.DrawImage($sourceBitmap,0,0,[int]$size,[int]$size)
                } finally { $graphics.Dispose() }
                $bitmap.Save((Join-Path $stage "App\AppInfo\appicon_$size.png"),[System.Drawing.Imaging.ImageFormat]::Png)
            } finally { $bitmap.Dispose() }
        } finally { $sourceBitmap.Dispose() }
    } finally { $ico.Dispose() }
}
Write-Host 'PortableApps.com appinfo.ini and 16/32/75/128/256px official PNG icons created.'

if (-not (Test-Path $compiler)) { throw 'Windows .NET Framework compiler missing' }
$launcher = Join-Path $stage 'SandboxiePlusPortable.exe'
$source = Join-Path $repo 'builder\SandboxiePlusPortable.cs'
if (-not (Test-Path $source)) { throw "Missing launcher source: $source" }
& $compiler /nologo /target:winexe /reference:System.Windows.Forms.dll "/win32icon:$icon" "/out:$launcher" $source
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $launcher)) { throw 'Launcher compilation failed' }

@"
Community portable packaging of official Sandboxie Plus $ReleaseTag
Source: https://github.com/sandboxie-plus/Sandboxie
Official portable extraction, x64/ARM64 as selected
Requires Administrator permission to load driver at runtime

This package is NOT an official Sandboxie/PortableApps.com release.
Do not launch the inner SandMan.exe directly: run SandboxiePlusPortable.exe.
Preserve Data during upgrades. Never replace App while SbieDrv/SbieSvc is registered.
"@ | Set-Content (Join-Path $stage 'Other\PACKAGE-INFO.txt') -Encoding UTF8
@"
Sandboxie Plus source and licensing information:
https://github.com/sandboxie-plus/Sandboxie/blob/$ReleaseTag/LICENSE.Plus
https://github.com/sandboxie-plus/Sandboxie/blob/$ReleaseTag/LICENSE.Classic
https://github.com/sandboxie-plus/Sandboxie
"@ | Set-Content (Join-Path $stage 'Other\LICENSE-LINKS.txt') -Encoding UTF8

$zip = Join-Path $out "SandboxiePlusPortable-$version-$Architecture.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path $stage -DestinationPath $zip -CompressionLevel Optimal
python builder/verify_zip.py $zip
if ($LASTEXITCODE -ne 0) { throw 'Archive verification failed' }
Write-Host "Finished: $zip"
