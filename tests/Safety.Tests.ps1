$ErrorActionPreference = 'Stop'
$utility = Join-Path $PSScriptRoot '../scripts/dotfiles/Hide-DotFolders.ps1'
$fixture = Join-Path ([System.IO.Path]::GetTempPath()) ('dotfolder-safety-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
$root = New-Item -ItemType Directory -Path (Join-Path $fixture 'root')
$folder = New-Item -ItemType Directory -Path (Join-Path $root.FullName '.test')
$outside = New-Item -ItemType Directory -Path (Join-Path $fixture 'outside')
$manifest = Join-Path $fixture 'dotfolders-run.json'
function Assert([bool] $Condition, [string] $Message) { if (-not $Condition) { throw $Message } }
function Expect-Failure([scriptblock] $Operation) {
    $failed = $false
    try { & $Operation | Out-Null } catch { $failed = $true }
    Assert $failed 'Expected a terminating error'
}
function Is-Hidden([string] $Target) { return [bool]((Get-Item -LiteralPath $Target -Force).Attributes -band [System.IO.FileAttributes]::Hidden) }

$preview = @(& $utility -Path $root.FullName -ManifestPath $manifest -WhatIf)
$summary = $preview | Where-Object Status -eq 'Summary'
Assert ($summary.Previewed -eq 1 -and $summary.Changed -eq 0) 'Wrong preview summary'
Assert (-not (Test-Path -LiteralPath ($manifest + '.lock'))) 'Preview created a lock'

# Another run owns this record: refuse before changing attributes.
$held = [System.IO.File]::Open(($manifest + '.lock'), 'CreateNew', 'Write', 'None')
try {
    Expect-Failure { & $utility -Path $root.FullName -ManifestPath $manifest }
    Assert (-not (Is-Hidden $folder.FullName)) 'Lock contention changed a folder'
    Assert (Test-Path -LiteralPath ($manifest + '.lock')) 'Foreign lock was deleted'
} finally { $held.Dispose(); [System.IO.File]::Delete(($manifest + '.lock')) }

$result = @(& $utility -Path $root.FullName -ManifestPath $manifest)
Assert (($result | Where-Object Status -eq 'Summary').Changed -eq 1) 'Wrong apply summary'
$original = [System.IO.File]::ReadAllText($manifest)
Expect-Failure { & $utility -Path $root.FullName -ManifestPath $manifest }
Assert ([System.IO.File]::ReadAllText($manifest) -eq $original) 'Existing manifest overwritten'

# A later invalid entry must prevent restoration of the earlier valid one.
$bad = Join-Path $fixture 'dotfolders-bad.json'
@{ Version = 1; Root = $root.FullName; Entries = @(@{ Path = $folder.FullName }, @{ Path = $outside.FullName }) } |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $bad -Encoding UTF8
Expect-Failure { & $utility -RestoreManifest $bad }
Assert (Is-Hidden $folder.FullName) 'Partial restoration happened before validation finished'

# Junction in an ancestor, even though the final folder itself is ordinary.
$outsideChild = New-Item -ItemType Directory -Path (Join-Path $outside.FullName '.child')
$junction = New-Item -ItemType Junction -Path (Join-Path $root.FullName 'alias') -Target $outside.FullName
@{ Version = 1; Root = $root.FullName; Entries = @(@{ Path = (Join-Path $junction.FullName '.child') }) } |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $bad -Encoding UTF8
Expect-Failure { & $utility -RestoreManifest $bad }
Expect-Failure { & $utility -Path $junction.FullName -WhatIf }

& $utility -RestoreManifest $manifest | Out-Null
Assert (-not (Is-Hidden $folder.FullName)) 'Valid recovery failed'
Assert (-not (Test-Path -LiteralPath ($manifest + '.lock'))) 'Owned lock leaked'

# Simulate persistence failure on the second folder. The first recovery record
# must remain readable, and the second folder must not change.
$persistRoot = New-Item -ItemType Directory -Path (Join-Path $fixture 'persistence')
$first = New-Item -ItemType Directory -Path (Join-Path $persistRoot.FullName '.a')
$second = New-Item -ItemType Directory -Path (Join-Path $persistRoot.FullName '.b')
$persistManifest = Join-Path $fixture 'dotfolders-persistence.json'
$fault = @{ Calls = 0 }
function ConvertTo-Json {
    [CmdletBinding()]param([Parameter(ValueFromPipeline = $true)]$InputObject, [int]$Depth)
    process {
        $fault.Calls++
        if ($fault.Calls -eq 2) { throw 'Simulated manifest serialization failure' }
        Microsoft.PowerShell.Utility\ConvertTo-Json -InputObject $InputObject -Depth $Depth
    }
}
try { Expect-Failure { & $utility -Path $persistRoot.FullName -ManifestPath $persistManifest } }
finally { Remove-Item Function:\ConvertTo-Json }
Assert (Is-Hidden $first.FullName) 'First operation did not complete'
Assert (-not (Is-Hidden $second.FullName)) 'Changed folder despite persistence failure'
Assert ((Get-Content -LiteralPath $persistManifest -Raw | ConvertFrom-Json).Entries.Count -eq 1) 'Previous manifest damaged'
& $utility -RestoreManifest $persistManifest | Out-Null
Assert (-not (Is-Hidden $first.FullName)) 'Recovery after persistence failure failed'
# Check the process exit status used by Task Scheduler.
$hostExe = (Get-Process -Id $PID).Path
$ErrorActionPreference = 'Continue'
& $hostExe -NoProfile -ExecutionPolicy Bypass -File $utility -RestoreManifest $bad *> $null
$ErrorActionPreference = 'Stop'
Assert ($LASTEXITCODE -ne 0) 'Invalid recovery reported process success'
Write-Output 'PASS: summaries, exclusive records, preflight, junction rejection, persistence failure, process failure status.'
