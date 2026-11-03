$ErrorActionPreference = 'Stop'
$audit = Join-Path $PSScriptRoot '../scripts/dotfiles/Audit-DotFolders.ps1'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('audit-test-' + [guid]::NewGuid().ToString('N'))
$root = Join-Path $fixture 'input'
$output = Join-Path $fixture 'reports'
foreach ($name in @('.cache', '.ssh/.cache', 'normal/.deep/.deeper', 'excluded/.private', '=1+1', 'A&B')) {
    New-Item -ItemType Directory -Path (Join-Path $root $name) -Force | Out-Null
}
foreach ($name in @('=1+1', 'A&B')) {
    $item = Get-Item -LiteralPath (Join-Path $root $name)
    $item.Attributes = $item.Attributes -bor [IO.FileAttributes]::Hidden
}
function Assert([bool] $Value, [string] $Message) { if (-not $Value) { throw $Message } }
function Expect-Failure([scriptblock] $Operation) {
    $failed = $false
    try { & $Operation | Out-Null } catch { $failed = $true }
    Assert $failed 'Expected failure'
}
$before = @(Get-ChildItem -LiteralPath $root -Recurse -Force | Select-Object FullName,Attributes | ConvertTo-Json)
$preview = & $audit -Path $root -OutputDirectory $output -WhatIf
Assert ($preview.MatchingDirectories -eq 4) 'Immediate depth must include four matches'
Assert (-not (Test-Path -LiteralPath $output)) 'Preview wrote reports'
$result = & $audit -Path $root -OutputDirectory $output -MaxDepth 2 -Exclude EXCLUDED
$report = Get-Content -LiteralPath (Join-Path $result.ReportDirectory 'report.json') -Raw | ConvertFrom-Json
Assert ($report.Rows.Count -eq 6) 'Wrong depth/exclusion result'
Assert (@($report.Rows | Where-Object Name -eq '.deeper').Count -eq 0) 'Depth limit ignored'
Assert (@($report.Rows | Where-Object Name -eq '.private').Count -eq 0) 'Exclusion not pruned'
Assert (($report.Rows | Where-Object Path -like '*\.ssh\.cache').Recommendation -eq 'Keep') 'Sensitive parent must override cache heuristic'
$csv = Import-Csv -LiteralPath (Join-Path $result.ReportDirectory 'report.csv')
Assert (@($csv | Where-Object Name -eq "'=1+1").Count -eq 1) 'Formula-like name not protected'
$html = Get-Content -LiteralPath (Join-Path $result.ReportDirectory 'report.html') -Raw
Assert ($html.Contains('A&amp;B')) 'HTML data not encoded'
$again = & $audit -Path $root -OutputDirectory $output
Assert ($again.ReportDirectory -ne $result.ReportDirectory) 'Repeated audit reused output'
Assert (Test-Path -LiteralPath (Join-Path $result.ReportDirectory 'report.json')) 'Previous report overwritten'
$after = @(Get-ChildItem -LiteralPath $root -Recurse -Force | Select-Object FullName,Attributes | ConvertTo-Json)
Assert (($before -join '') -eq ($after -join '')) 'Scanned tree changed'
Expect-Failure { & $audit -Path $root -OutputDirectory (Join-Path $root 'reports') }
Expect-Failure { & $audit -Path $root -OutputDirectory $output -Exclude '*.cache' }
Expect-Failure { & $audit -Path $root -OutputDirectory $output -MaxDepth 0 }
$empty = New-Item -ItemType Directory -Path (Join-Path $fixture 'empty')
$emptyRun = & $audit -Path $empty.FullName -OutputDirectory $output
$emptyData = Get-Content -LiteralPath (Join-Path $emptyRun.ReportDirectory 'report.json') -Raw | ConvertFrom-Json
Assert ($emptyData.Rows -is [array] -and $emptyData.Rows.Count -eq 0) 'Empty JSON rows must be an array'
Assert ((Get-Content -LiteralPath (Join-Path $emptyRun.ReportDirectory 'report.csv')).StartsWith('"Name"')) 'Empty CSV missing header'
# Simulate an inaccessible subtree without changing ACLs on the host.
$probe = @{ Blocked = (Join-Path $root 'normal') }
function Get-ChildItem {
    [CmdletBinding()]param($LiteralPath, [switch]$Directory, [switch]$Force)
    if ($LiteralPath -eq $probe.Blocked) { throw 'Simulated access denied' }
    Microsoft.PowerShell.Management\Get-ChildItem -LiteralPath $LiteralPath -Directory:$Directory -Force:$Force
}
try { Expect-Failure { & $audit -Path $root -OutputDirectory $output -MaxDepth 2 } }
finally { Remove-Item Function:\Get-ChildItem }
$incomplete = @(Get-ChildItem -LiteralPath $output -Directory | ForEach-Object {
    Get-Content -LiteralPath (Join-Path $_.FullName 'report.json') -Raw | ConvertFrom-Json
} | Where-Object { -not $_.Summary.CompleteWithinScope })
Assert ($incomplete.Count -eq 1 -and $incomplete[0].Errors.Count -eq 1) 'Scan error not preserved'
# Real junctions must be reported but never followed.
$outside = New-Item -ItemType Directory -Path (Join-Path $fixture 'outside/.external') -Force
$junction = New-Item -ItemType Junction -Path (Join-Path $root '.link') -Target $outside.Parent.FullName
$linkedRun = & $audit -Path $root -OutputDirectory $output -MaxDepth 3
$linkedData = Get-Content -LiteralPath (Join-Path $linkedRun.ReportDirectory 'report.json') -Raw | ConvertFrom-Json
Assert (@($linkedData.Rows | Where-Object Name -eq '.external').Count -eq 0) 'Followed junction'
Assert (($linkedData.Rows | Where-Object Name -eq '.link').ReparsePoint) 'Junction not marked'
Expect-Failure { & $audit -Path $junction.FullName -OutputDirectory $output }
Write-Output 'PASS: audit depth, exclusions, read-only scan, exports, errors, empty results and junctions.'
