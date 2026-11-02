#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string] $ConfigPath)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ((Get-Item -LiteralPath $ConfigPath).Length -gt 65536) { throw 'Configuration exceeds 64 KiB.' }
$config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($config.Version -ne 1 -or $config.Path -isnot [string] -or $config.Recurse -isnot [bool] -or $config.Exclude -isnot [array]) {
    throw 'Invalid task configuration.'
}
foreach ($name in $config.Exclude) { if ($name -isnot [string]) { throw 'Exclusions must be strings.' } }
$stateRoot = Split-Path -Parent ([System.IO.Path]::GetFullPath($ConfigPath))
$manifest = Join-Path $stateRoot ('dotfolders-' + [guid]::NewGuid().ToString('N') + '.json')
& (Join-Path $PSScriptRoot 'Hide-DotFolders.ps1') -Path $config.Path -Recurse:$config.Recurse -Exclude $config.Exclude -ManifestPath $manifest
