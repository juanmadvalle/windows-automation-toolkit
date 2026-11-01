#Requires -Version 5.1
<#
.SYNOPSIS
Hide dot-prefixed directories or restore folders recorded by a previous run.
.EXAMPLE
./Hide-DotFolders.ps1 -Path $env:USERPROFILE -WhatIf
.EXAMPLE
./Hide-DotFolders.ps1 -Path 'D:/Projects' -Recurse -Exclude node_modules,.git -WhatIf
.EXAMPLE
./Hide-DotFolders.ps1 -RestoreManifest './dotfolders-RUN.json' -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'Hide')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Hide')]
    [string] $Path,

    [Parameter(ParameterSetName = 'Hide')]
    [switch] $Recurse,

    [Parameter(ParameterSetName = 'Hide')]
    [string[]] $Exclude = @(),

    [Parameter(ParameterSetName = 'Hide')]
    [string] $ManifestPath = (Join-Path (Get-Location) ('dotfolders-' + [guid]::NewGuid().ToString('N') + '.json')),

    [Parameter(Mandatory = $true, ParameterSetName = 'Restore')]
    [string] $RestoreManifest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'This script requires Windows.' }
$hiddenFlag = [System.IO.FileAttributes]::Hidden
$linkFlag = [System.IO.FileAttributes]::ReparsePoint

function Save-Manifest {
    param([string] $Destination, [object] $Data)
    $temporary = $Destination + '.tmp'
    $Data | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $temporary -Encoding UTF8
    Move-Item -LiteralPath $temporary -Destination $Destination -Force
}

if ($PSCmdlet.ParameterSetName -eq 'Restore') {
    $record = Get-Content -LiteralPath $RestoreManifest -Raw | ConvertFrom-Json
    if ($record.Version -ne 1) { throw 'Unsupported manifest version.' }
    $restoreRoot = [System.IO.Path]::GetFullPath([string]$record.Root).TrimEnd('\') + '\'
    foreach ($entry in @($record.Entries)) {
        try {
            $fullName = [System.IO.Path]::GetFullPath([string]$entry.Path)
            if (-not $fullName.StartsWith($restoreRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw 'Manifest entry is outside the recorded root.'
            }
            $folder = Get-Item -LiteralPath $fullName -Force
            if (-not $folder.PSIsContainer -or ($folder.Attributes -band $linkFlag)) {
                throw 'Manifest entry must be an ordinary directory.'
            }
            if (($folder.Attributes -band $hiddenFlag) -and $PSCmdlet.ShouldProcess($fullName, 'Remove Hidden attribute')) {
                $folder.Attributes = $folder.Attributes -band (-bnot $hiddenFlag)
                [pscustomobject]@{ Path = $fullName; Status = 'Restored' }
            }
        } catch {
            Write-Error -Message "Cannot restore '$($entry.Path)': $_" -ErrorAction Continue
        }
    }
    return
}

$root = Get-Item -LiteralPath $Path -Force
if (-not $root.PSIsContainer -or ($root.Attributes -band $linkFlag)) {
    throw 'Path must be an ordinary filesystem directory.'
}
if ($root.PSProvider.Name -ne 'FileSystem') { throw 'Path must use the filesystem provider.' }
$manifest = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ManifestPath)
if (Test-Path -LiteralPath $manifest) { throw 'Manifest already exists. Choose a new manifest path.' }
if (-not (Test-Path -LiteralPath (Split-Path -Parent $manifest) -PathType Container)) {
    throw 'Manifest parent directory must already exist.'
}
$record = [ordered]@{ Version = 1; Root = $root.FullName; Entries = @() }
$queue = New-Object 'System.Collections.Generic.Queue[string]'
$queue.Enqueue($root.FullName)
while ($queue.Count -gt 0) {
    $directory = $queue.Dequeue()
    try {
        $children = @(Get-ChildItem -LiteralPath $directory -Directory -Force)
    } catch {
        Write-Error -Message "Cannot enumerate '$directory': $_" -ErrorAction Continue
        continue
    }
    foreach ($folder in $children) {
        # Exclusions prune complete subtrees, not just the final output.
        if ($Exclude -contains $folder.Name -or ($folder.Attributes -band $linkFlag)) { continue }
        if ($Recurse) { $queue.Enqueue($folder.FullName) }
        if (-not $folder.Name.StartsWith('.') -or ($folder.Attributes -band $hiddenFlag)) { continue }
        if ($PSCmdlet.ShouldProcess($folder.FullName, 'Add Hidden attribute')) {
            # Persist recovery intent before mutation, including interrupted changes.
            $record.Entries += [ordered]@{ Path = $folder.FullName }
            Save-Manifest -Destination $manifest -Data $record
            try {
                $folder.Attributes = $folder.Attributes -bor $hiddenFlag
                [pscustomobject]@{ Path = $folder.FullName; Status = 'Hidden'; Manifest = $manifest }
            } catch {
                Write-Error -Message "Cannot hide '$($folder.FullName)': $_" -ErrorAction Continue
            }
        }
    }
}
