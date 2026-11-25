[CmdletBinding()]
param()

# Local build that mirrors CurseForge's automatic packager: the repository root becomes the
# PreflightForever addon folder, minus dotfiles, git-ignored paths and the .pkgmeta "ignore" list.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$addonName = 'PreflightForever'
$outputDirectory = Join-Path $projectRoot 'dist'
$stagingDirectory = Join-Path $outputDirectory 'package'
$packagedAddon = Join-Path $stagingDirectory $addonName

function Get-IgnoreList([string]$pkgmetaPath) {
    $entries = @()
    $inIgnore = $false
    foreach ($line in Get-Content -LiteralPath $pkgmetaPath) {
        if ($line -match '^ignore:\s*$') { $inIgnore = $true; continue }
        if ($inIgnore) {
            if ($line -match '^\s+-\s+(.+?)\s*$') { $entries += $Matches[1].Trim('"', "'").TrimEnd('/') }
            elseif ($line -match '^\S') { $inIgnore = $false }
        }
    }
    foreach ($entry in $entries) {
        if ($entry -match '[/\\]') { throw "Package.ps1 only supports top-level .pkgmeta ignore entries: $entry" }
    }
    return $entries
}

$excluded = @(Get-IgnoreList (Join-Path $projectRoot '.pkgmeta'))
$excluded += Get-Content -LiteralPath (Join-Path $projectRoot '.gitignore') |
    Where-Object { $_ -and -not $_.StartsWith('#') } | ForEach-Object { $_.Trim().TrimEnd('/') }

$items = Get-ChildItem -LiteralPath $projectRoot -Force | Where-Object {
    $name = $_.Name
    -not $name.StartsWith('.') -and -not ($excluded | Where-Object { $name -like $_ })
}
if (-not ($items | Where-Object { $_.Name -eq "$addonName.toc" })) { throw "$addonName.toc must be packaged." }

# Start from an empty staging folder so removed files never linger in the zip.
if (Test-Path -LiteralPath $packagedAddon) { Remove-Item -LiteralPath $packagedAddon -Recurse -Force }
New-Item -ItemType Directory -Path $packagedAddon -Force | Out-Null
foreach ($item in $items) {
    Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $packagedAddon $item.Name) -Recurse -Force
}

$versionLine = Get-Content -LiteralPath (Join-Path $projectRoot "$addonName.toc") | Where-Object { $_ -match '^## Version: ' }
$addonVersion = ($versionLine -replace '^## Version: ', '').Trim()
if ($addonVersion -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid addon version.' }
$archive = Join-Path $outputDirectory ($addonName + '-' + $addonVersion + '.zip')
# Write the zip directly: Windows PowerShell 5.1's Compress-Archive stores backslash paths,
# which other unzip tools (and addon sites) can read as flat file names.
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
$stagingRoot = [System.IO.Path]::GetFullPath($stagingDirectory).TrimEnd('\') + '\'
$zip = [System.IO.Compression.ZipFile]::Open($archive, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in Get-ChildItem -LiteralPath $packagedAddon -File -Recurse) {
        $entryName = $file.FullName.Substring($stagingRoot.Length) -replace '\\', '/'
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $file.FullName, $entryName, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
} finally {
    $zip.Dispose()
}
Write-Output $archive
