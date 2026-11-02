# Scheduler commands are mocked. These tests never register a real task.
$ErrorActionPreference = 'Stop'
$manage = Join-Path $PSScriptRoot '../scripts/dotfiles/Manage-DotFoldersTask.ps1'
$runner = Join-Path $PSScriptRoot '../scripts/dotfiles/Run-DotFoldersTask.ps1'
$fixture = Join-Path ([System.IO.Path]::GetTempPath()) ('dotfolder task ' + [guid]::NewGuid().ToString('N'))
$root = New-Item -ItemType Directory -Path (Join-Path $fixture "books with ' quotes") -Force
$folder = New-Item -ItemType Directory -Path (Join-Path $root.FullName '.test')
$state = Join-Path $fixture 'state with spaces'
$probe = @{ Existing = $null; Registered = $null; Removed = $false }


function Assert([bool] $Condition, [string] $Message) { if (-not $Condition) { throw $Message } }
function Expect-Failure([scriptblock] $Operation) {
    $failed = $false
    try { & $Operation | Out-Null } catch { $failed = $true }
    Assert $failed 'Expected failure'
}
function Get-ScheduledTask { [CmdletBinding()]param($TaskName, $TaskPath) return $probe.Existing }
function New-ScheduledTaskAction { param($Execute, $Argument) return @{ Execute = $Execute; Arguments = $Argument } }
function New-ScheduledTaskTrigger { param([switch]$AtLogOn, $User) return @{ User = $User } }
function New-ScheduledTaskPrincipal { param($UserId, $LogonType, $RunLevel) return @{ RunLevel = $RunLevel; LogonType = $LogonType } }
function New-ScheduledTaskSettingsSet { param($MultipleInstances, $ExecutionTimeLimit) return @{ MultipleInstances = $MultipleInstances } }
function Register-ScheduledTask {
    param($TaskName, $TaskPath, $Action, $Trigger, $Principal, $Settings, $Description)
    $probe.Registered = @{ Action = $Action; Principal = $Principal; Settings = $Settings; Description = $Description }
}
function Unregister-ScheduledTask { param($TaskName, $TaskPath, [switch]$Confirm) $probe.Removed = $true }

& $manage -Action Install -Path $root.FullName -StateDirectory $state -WhatIf
Assert (-not (Test-Path -LiteralPath $state)) 'Preview wrote configuration'
Assert ($null -eq $probe.Registered) 'Preview registered a task'
& $manage -Action Install -Path $root.FullName -StateDirectory $state
Assert ($probe.Registered.Principal.RunLevel -eq 'Limited') 'Task is elevated'
Assert ($probe.Registered.Settings.MultipleInstances -eq 'IgnoreNew') 'Overlapping task runs allowed'
Assert ($probe.Registered.Action.Arguments.Contains('-ConfigPath "' + $state)) 'Config path not quoted'
Assert (-not $probe.Registered.Action.Arguments.Contains($root.FullName)) 'User target interpolated into command line'
$config = Join-Path $state 'HideDotFolders-Toolkit.json'
& $runner -ConfigPath $config | Out-Null
Assert ([bool]((Get-Item -LiteralPath $folder.FullName -Force).Attributes -band [System.IO.FileAttributes]::Hidden)) 'Runner did not use configuration'
$probe.Existing = [pscustomobject]@{ Description = 'Unrelated task' }
Expect-Failure { & $manage -Action Install -Path $root.FullName -StateDirectory $state }
Expect-Failure { & $manage -Action Uninstall }
Assert (-not $probe.Removed) 'Unrelated task removed'
$probe.Existing = [pscustomobject]@{ Description = $probe.Registered.Description }
& $manage -Action Uninstall
Assert $probe.Removed 'Owned task was not removed'
Assert (Test-Path -LiteralPath $config) 'Uninstall removed recovery configuration'
Write-Output 'PASS: task preview, ownership, limited privilege, path quoting, runner, and retained state.'

