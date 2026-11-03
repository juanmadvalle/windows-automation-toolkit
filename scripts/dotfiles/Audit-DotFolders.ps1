#Requires -Version 5.1
<#
.SYNOPSIS
Report hidden and dot-prefixed directories without changing the scanned tree.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][Alias('Root')][string] $Path,
    [Parameter(Mandatory = $true)][string] $OutputDirectory,
    [ValidateRange(1, 100)][int] $MaxDepth = 1,
    [string[]] $Exclude = @()
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'This script requires Windows.' }

function Assert-NoLinks([string] $Target) {
    $current = [IO.Path]::GetFullPath($Target)
    while ($current) {
        $item = $null
        try { $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop }
        catch { if ($_.CategoryInfo.Category -ne 'ObjectNotFound') { throw } }
        if ($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Linked paths are unsupported: $current"
        }
        $parent = Split-Path -Parent $current
        if ($parent -eq $current) { break }
        $current = $parent
    }
}
function Encode-Html([object] $Value) { [Net.WebUtility]::HtmlEncode([string]$Value) }
function Protect-Cell([object] $Value) {
    $text = [string]$Value
    if ($text -match '^[\s\uFEFF]*[=+@-]' -or $text -match '^[\t\r\n]') { return "'" + $text }
    return $text
}
function Write-NewFile([string] $Target, [string] $Content) {
    $stream = [IO.File]::Open($Target, 'CreateNew', 'Write', 'None')
    try {
        $bytes = [Text.UTF8Encoding]::new($true).GetPreamble() + [Text.Encoding]::UTF8.GetBytes($Content)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
    } finally { $stream.Dispose() }
}

foreach ($name in $Exclude) {
    if ([string]::IsNullOrWhiteSpace($name) -or $name -match '[\\/*?]' -or $name -in @('.', '..')) {
        throw 'Exclusions must be exact directory names, not paths or patterns.'
    }
}
$root = Get-Item -LiteralPath $Path -Force
if (-not $root.PSIsContainer -or $root.PSProvider.Name -ne 'FileSystem') { throw 'Path must be a filesystem directory.' }
Assert-NoLinks $root.FullName
$rootPath = $root.FullName.TrimEnd('\')
$output = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
Assert-NoLinks $output
if ($output.TrimEnd('\').Equals($rootPath, [StringComparison]::OrdinalIgnoreCase) -or
    $output.StartsWith($rootPath + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'OutputDirectory must be outside the scanned tree.'
}
if ((Test-Path -LiteralPath $output) -and -not (Test-Path -LiteralPath $output -PathType Container)) {
    throw 'OutputDirectory must be a directory.'
}
$rows = [Collections.Generic.List[object]]::new()
$issues = [Collections.Generic.List[object]]::new()
$queue = [Collections.Generic.Queue[object]]::new()
$queue.Enqueue(@{ Path = $root.FullName; Depth = 0 })
$visited = 0; $excluded = 0; $links = 0; $depthLimited = 0
while ($queue.Count -gt 0) {
    $current = $queue.Dequeue()
    try {
        Assert-NoLinks $current.Path
        $children = @(Get-ChildItem -LiteralPath $current.Path -Directory -Force -ErrorAction Stop)
        $visited++
    } catch {
        $issues.Add([pscustomobject]@{ Path = $current.Path; Error = $_.Exception.Message })
        continue
    }
    foreach ($folder in $children) {
        if ($Exclude -contains $folder.Name) { $excluded++; continue }
        $depth = $current.Depth + 1
        $linked = [bool]($folder.Attributes -band [IO.FileAttributes]::ReparsePoint)
        $hidden = [bool]($folder.Attributes -band [IO.FileAttributes]::Hidden)
        $system = [bool]($folder.Attributes -band [IO.FileAttributes]::System)
        if ($linked) { $links++ }
        elseif ($depth -lt $MaxDepth) { $queue.Enqueue(@{ Path = $folder.FullName; Depth = $depth }) }
        else { $depthLimited++ }
        if (-not ($hidden -or $folder.Name.StartsWith('.'))) { continue }
        $category = 'Manual review'
        $reason = 'A name or hidden attribute does not establish whether a folder is needed.'
        if ($linked) {
            $category = 'Keep / not inspected'; $reason = 'Reparse point; its contents are not traversed.'
        } elseif ($system -or $folder.FullName -match '\\(AppData|\.ssh|\.gnupg|\.aws|\.azure|\.kube|\.afirma|\.fnmt|\.git|\.hg|\.svn)(\\|$)') {
            $category = 'Keep'; $reason = 'May contain application data, credentials, certificates or version history.'
        } elseif ($folder.FullName -match '\\(\.codex|\.claude|\.copilot|\.gemini|\.vscode|\.config|\.local|\.docker|\.conda|\.venv)(\\|$)') {
            $category = 'Review in owning application'; $reason = 'May contain configuration, environments, sessions or user data.'
        } elseif ($folder.Name -in @('.cache', '.npm', '.parcel-cache', '.next', '.nuxt', '.pytest_cache', '.mypy_cache', '.ruff_cache', '.sass-cache', '.turbo')) {
            $category = 'Possible cache (unverified)'; $reason = 'Common cache name only; review contents and use the owning application to clean.'
        }
        $rows.Add([pscustomobject][ordered]@{
            Name = $folder.Name; Path = $folder.FullName; Depth = $depth
            Recommendation = $category; Reason = $reason
            Hidden = $hidden; System = $system; ReparsePoint = $linked
        })
    }
}
$sorted = @($rows | Sort-Object Path)
$summary = [pscustomobject][ordered]@{
    Root = $root.FullName; MaxDepth = $MaxDepth; Exclude = @($Exclude)
    EnumeratedDirectories = $visited; MatchingDirectories = $rows.Count
    ExcludedSubtrees = $excluded; SkippedLinks = $links; DepthLimitedDirectories = $depthLimited
    Errors = $issues.Count; CompleteWithinScope = ($issues.Count -eq 0); ReportDirectory = $null
}
if ($PSCmdlet.ShouldProcess($output, 'Write private audit reports (HTML, CSV and JSON)')) {
    Assert-NoLinks $output
    New-Item -ItemType Directory -Path $output -Force | Out-Null
    $run = Join-Path $output ('dotfolder-audit-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $run -ErrorAction Stop | Out-Null
    $summary.ReportDirectory = $run
    $data = [ordered]@{ Version = 1; Summary = $summary; Rows = $sorted; Errors = @($issues.ToArray()) }
    Write-NewFile (Join-Path $run 'report.json') ($data | ConvertTo-Json -Depth 8)
    $columns = @('Name','Path','Depth','Recommendation','Reason','Hidden','System','ReparsePoint')
    $safeRows = @(foreach ($row in $sorted) {
        $safe = [ordered]@{}
        foreach ($column in $columns) { $safe[$column] = Protect-Cell $row.$column }
        [pscustomobject]$safe
    })
    $csv = if ($safeRows.Count) { ($safeRows | ConvertTo-Csv -NoTypeInformation) -join "`r`n" }
           else { '"' + ($columns -join '","') + '"' }
    Write-NewFile (Join-Path $run 'report.csv') ($csv + "`r`n")
    $table = foreach ($row in $sorted) {
        '<tr>' + (($columns | ForEach-Object { '<td>' + (Encode-Html $row.$_) + '</td>' }) -join '') + '</tr>'
    }
    $errorsHtml = ($issues | ForEach-Object { '<li>' + (Encode-Html $_.Path) + ': ' + (Encode-Html $_.Error) + '</li>' }) -join ''
    $html = '<!doctype html><html lang="en"><meta charset="utf-8"><title>Folder audit</title>' +
        '<style>body{font-family:Segoe UI,sans-serif;margin:2rem}table{border-collapse:collapse}td,th{border:1px solid #ccc;padding:.5rem;overflow-wrap:anywhere}</style>' +
        '<h1>Hidden and dot-folder audit</h1><p>Root: ' + (Encode-Html $root.FullName) + '</p>' +
        '<p>Maximum depth: ' + $MaxDepth + '. Exclusions: ' + (Encode-Html ($Exclude -join ', ')) + '</p>' +
        '<p>Matches: ' + $rows.Count + '. Scan errors: ' + $issues.Count + '. Complete within requested scope: ' + $summary.CompleteWithinScope + '</p>' +
        '<p>Private report: contains local paths. No scanned files or attributes were changed. Recommendations are heuristics, not permission to delete. No file contents or reclaimable sizes were inspected. Links were not followed. Depth limits and exclusions omit subtrees.</p>' +
        '<table><tr>' + (($columns | ForEach-Object { '<th>' + $_ + '</th>' }) -join '') + '</tr>' + ($table -join '') +
        '</table><h2>Scan errors</h2><ul>' + $errorsHtml + '</ul></html>'
    Write-NewFile (Join-Path $run 'report.html') $html
}
$summary
if ($issues.Count) { throw 'Audit incomplete: inspect the reported scan errors.' }
