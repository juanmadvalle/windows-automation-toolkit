$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot '../scripts/dotfiles/Hide-DotFolders.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('dotfolder-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
foreach ($name in @('.visible', '.already', 'ordinary', 'excluded', 'excluded/.nested', 'ordinary/.nested')) {
    New-Item -ItemType Directory -Path (Join-Path $testRoot $name) -Force | Out-Null
}
$already = Get-Item -LiteralPath (Join-Path $testRoot '.already') -Force
$already.Attributes = $already.Attributes -bor [System.IO.FileAttributes]::Hidden
$manifest = Join-Path $testRoot 'dotfolders-test.json'
function Assert-Hidden([string] $Name, [bool] $Expected) {
    $item = Get-Item -LiteralPath (Join-Path $testRoot $Name) -Force
    $actual = [bool]($item.Attributes -band [System.IO.FileAttributes]::Hidden)
    if ($actual -ne $Expected) { throw "Hidden mismatch: $Name" }
}
& $script -Path $testRoot -Recurse -ManifestPath $manifest -WhatIf
Assert-Hidden '.visible' $false
if (Test-Path -LiteralPath $manifest) { throw 'WhatIf created a manifest' }
& $script -Path $testRoot -Recurse -Exclude excluded -ManifestPath $manifest | Out-Null
Assert-Hidden '.visible' $true
Assert-Hidden 'ordinary/.nested' $true
Assert-Hidden 'excluded/.nested' $false
Assert-Hidden 'ordinary' $false
& $script -RestoreManifest $manifest -WhatIf
Assert-Hidden '.visible' $true
& $script -RestoreManifest $manifest | Out-Null
Assert-Hidden '.visible' $false
Assert-Hidden 'ordinary/.nested' $false
Assert-Hidden '.already' $true
Write-Output "PASS: preview, recursive exclusions, preservation, and restore. Fixture: $testRoot"
