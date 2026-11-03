#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'Hide')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Hide')][string] $Path,
    [Parameter(ParameterSetName = 'Hide')][switch] $Recurse,
    [Parameter(ParameterSetName = 'Hide')][string[]] $Exclude = @(),
    [Parameter(ParameterSetName = 'Hide')]
    [string] $ManifestPath = (Join-Path (Get-Location) ('dotfolders-' + [guid]::NewGuid().ToString('N') + '.json')),
    [Parameter(Mandatory = $true, ParameterSetName = 'Restore')][string] $RestoreManifest
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'This script requires Windows.' }
$hiddenFlag = [System.IO.FileAttributes]::Hidden
$linkFlag = [System.IO.FileAttributes]::ReparsePoint
$summary = [ordered]@{ Status = 'Summary'; Changed = 0; Skipped = 0; Previewed = 0; Failed = 0 }
$lock = $null
$lockPath = $null

function Assert-OrdinaryPath([string] $Target) {
    $current = [System.IO.Path]::GetFullPath($Target)
    while ($current) {
        $item = $null
        try { $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop }
        catch { if ($_.CategoryInfo.Category -ne 'ObjectNotFound') { throw } }
        if ($null -ne $item -and ($item.Attributes -band $linkFlag)) { throw "Linked paths are unsupported: $current" }
        $parent = Split-Path -Parent $current
        if ($parent -eq $current) { break }
        $current = $parent
    }
}
function Assert-AbsolutePath([object] $Value) {
    if ($Value -isnot [string] -or $Value -notmatch '^(?:[A-Za-z]:[\\/]|\\\\[^\\]+\\[^\\]+)') {
        throw 'Manifest paths must be absolute filesystem paths.'
    }
    if ($Value -match '[\x00-\x1f]' -or $Value.StartsWith('\\?\') -or $Value.StartsWith('\\.\')) { throw 'Unsupported manifest path.' }
}
function Save-Manifest([string] $Destination, [object] $Data) {
    $temporary = $Destination + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    $stream = $null
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes(($Data | ConvertTo-Json -Depth 5))
        if ($bytes.Length -gt 4194304) { throw 'Manifest exceeds 4 MiB; previous recovery data retained.' }
        $stream = [System.IO.File]::Open($temporary, 'CreateNew', 'Write', 'None')
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
        $stream.Dispose(); $stream = $null
        if ([System.IO.File]::Exists($Destination)) { [System.IO.File]::Replace($temporary, $Destination, [NullString]::Value) }
        else { [System.IO.File]::Move($temporary, $Destination) }
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
        if ([System.IO.File]::Exists($temporary)) { [System.IO.File]::Delete($temporary) }
    }
}
try {
    if ($PSCmdlet.ParameterSetName -eq 'Restore') {
        $manifest = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($RestoreManifest)
        Assert-OrdinaryPath $manifest
        if ((Get-Item -LiteralPath $manifest).Length -gt 4194304) { throw 'Manifest exceeds 4 MiB.' }
        $record = Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($record.Version -isnot [int] -and $record.Version -isnot [long]) { throw 'Invalid manifest version.' }
        if ($record.Version -ne 1 -or $record.Entries -isnot [array]) { throw 'Invalid manifest structure.' }
        Assert-AbsolutePath $record.Root
        $restoreRoot = [System.IO.Path]::GetFullPath($record.Root).TrimEnd('\', '/') + '\'
        Assert-OrdinaryPath $restoreRoot
        $validated = @()
        $seen = @{}
        # Preflight the entire manifest before any attribute changes.
        foreach ($entry in $record.Entries) {
            Assert-AbsolutePath $entry.Path
            $fullName = [System.IO.Path]::GetFullPath($entry.Path)
            if (-not $fullName.StartsWith($restoreRoot, [System.StringComparison]::OrdinalIgnoreCase) -or $seen.ContainsKey($fullName)) {
                throw 'Manifest contains an outside or duplicate path.'
            }
            Assert-OrdinaryPath $fullName
            $folder = Get-Item -LiteralPath $fullName -Force
            if (-not $folder.PSIsContainer) { throw 'Manifest entry must be a directory.' }
            $seen[$fullName] = $true
            # Entries recorded with an identity must still point at the same directory.
            $recordedTicks = if ($entry.PSObject.Properties['CreatedTicks']) { [string] $entry.CreatedTicks } else { $null }
            if ($recordedTicks -and $recordedTicks -ne [string] $folder.CreationTimeUtc.Ticks) {
                $summary.Skipped++
                Write-Warning "Skipped '$fullName': directory was replaced since the run."
                continue
            }
            $validated += $fullName
        }
        foreach ($fullName in $validated) {
            try {
                Assert-OrdinaryPath $fullName
                $folder = Get-Item -LiteralPath $fullName -Force
                if (-not ($folder.Attributes -band $hiddenFlag)) { $summary.Skipped++; continue }
                if ($PSCmdlet.ShouldProcess($fullName, 'Remove Hidden attribute')) {
                    if ($null -eq $lock) {
                        $lockPath = $manifest + '.lock'
                        $lock = [System.IO.File]::Open($lockPath, 'CreateNew', 'Write', 'None')
                    }
                    $folder.Attributes = $folder.Attributes -band (-bnot $hiddenFlag)
                    $summary.Changed++
                    [pscustomobject]@{ Path = $fullName; Status = 'Restored' }
                } else { $summary.Previewed++ }
            } catch { $summary.Failed++; Write-Warning "Cannot restore '$fullName': $_" }
        }
    } else {
        $root = Get-Item -LiteralPath $Path -Force
        if (-not $root.PSIsContainer -or $root.PSProvider.Name -ne 'FileSystem') { throw 'Path must be a filesystem directory.' }
        Assert-OrdinaryPath $root.FullName
        $manifest = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ManifestPath)
        Assert-OrdinaryPath $manifest
        if (Test-Path -LiteralPath $manifest) { throw 'Manifest already exists. Choose a new path.' }
        if (-not (Test-Path -LiteralPath (Split-Path -Parent $manifest) -PathType Container)) { throw 'Manifest parent must exist.' }
        $record = [ordered]@{ Version = 1; Root = $root.FullName; Entries = @() }
        $queue = New-Object 'System.Collections.Generic.Queue[string]'
        $queue.Enqueue($root.FullName)
        while ($queue.Count -gt 0) {
            $directory = $queue.Dequeue()
            try {
                Assert-OrdinaryPath $directory
                $children = @(Get-ChildItem -LiteralPath $directory -Directory -Force)
            } catch { $summary.Failed++; Write-Warning "Cannot enumerate '$directory': $_"; continue }
            foreach ($folder in $children) {
                if ($Exclude -contains $folder.Name -or ($folder.Attributes -band $linkFlag)) { $summary.Skipped++; continue }
                if ($Recurse) { $queue.Enqueue($folder.FullName) }
                if (-not $folder.Name.StartsWith('.') -or ($folder.Attributes -band $hiddenFlag)) { $summary.Skipped++; continue }
                if ($PSCmdlet.ShouldProcess($folder.FullName, 'Add Hidden attribute')) {
                    if ($null -eq $lock) {
                        $lockPath = $manifest + '.lock'
                        $lock = [System.IO.File]::Open($lockPath, 'CreateNew', 'Write', 'None')
                        if (Test-Path -LiteralPath $manifest) { throw 'Manifest appeared during startup; nothing overwritten.' }
                    }
                    $record.Entries += [ordered]@{ Path = $folder.FullName; CreatedTicks = [string] $folder.CreationTimeUtc.Ticks }
                    # A persistence failure aborts before this directory changes.
                    Save-Manifest $manifest $record
                    try {
                        Assert-OrdinaryPath $folder.FullName
                        $folder.Attributes = $folder.Attributes -bor $hiddenFlag
                        $summary.Changed++
                        [pscustomobject]@{ Path = $folder.FullName; Status = 'Hidden'; Manifest = $manifest }
                    } catch { $summary.Failed++; Write-Warning "Cannot hide '$($folder.FullName)': $_" }
                } else { $summary.Previewed++ }
            }
        }
    }
} catch { $summary.Failed++; throw }
finally {
    if ($null -ne $lock) { $lock.Dispose(); [System.IO.File]::Delete($lockPath) }
    [pscustomobject]$summary
}
if ($summary.Failed -gt 0) { throw "$($summary.Failed) operations failed; inspect warnings and recovery manifest." }
