#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][ValidateSet('Install', 'Status', 'Uninstall')][string] $Action,
    [ValidatePattern('^[A-Za-z0-9_-]{1,64}$')][string] $TaskName = 'HideDotFolders-Toolkit',
    [string] $Path,
    [switch] $Recurse,
    [string[]] $Exclude = @(),
    [string] $StateDirectory = (Join-Path $env:LOCALAPPDATA 'WindowsAutomationToolkit'),
    [string] $PowerShellPath = (Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$marker = 'Managed by windows-automation-toolkit/dotfolders-v1'
$existing = Get-ScheduledTask -TaskName $TaskName -TaskPath '\' -ErrorAction SilentlyContinue
if ($Action -eq 'Status') {
    if ($null -eq $existing) { [pscustomobject]@{ TaskName = $TaskName; State = 'NotInstalled' }; return }
    $existing | Select-Object TaskName, State, Description
    Get-ScheduledTaskInfo -TaskName $TaskName -TaskPath '\'
    return
}
if ($Action -eq 'Uninstall') {
    if ($null -eq $existing) { return }
    if ($existing.Description -ne $marker) { throw 'Refusing to remove a task not owned by this toolkit.' }
    if ($PSCmdlet.ShouldProcess($TaskName, 'Unregister toolkit task; retain recovery files')) {
        Unregister-ScheduledTask -TaskName $TaskName -TaskPath '\' -Confirm:$false
    }
    return
}
if ($null -ne $existing) { throw 'Task already exists. No existing task will be replaced.' }
if (-not $Path) { throw 'Install requires -Path.' }
$target = (Get-Item -LiteralPath $Path -Force).FullName
if (-not (Test-Path -LiteralPath $target -PathType Container)) { throw 'Path must be a directory.' }
$executable = (Get-Item -LiteralPath $PowerShellPath).FullName
$runner = Join-Path $PSScriptRoot 'Run-DotFoldersTask.ps1'
$stateRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($StateDirectory)
$config = Join-Path $stateRoot ($TaskName + '.json')
foreach ($value in @($config, $runner, $executable)) {
    if ($value -match '["\r\n]') { throw 'Unsupported character in task command path.' }
}
if (Test-Path -LiteralPath $config) { throw 'Configuration already exists. Choose another state directory or archive it first.' }
$user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$arguments = '-NoProfile -NonInteractive -WindowStyle Hidden -File "' + $runner + '" -ConfigPath "' + $config + '"'
if ($PSCmdlet.ShouldProcess($TaskName, "Install limited-user sign-in task for $target")) {
    New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
    $configStream = [System.IO.File]::Open($config, 'CreateNew', 'Write', 'None')
    try {
        $data = [ordered]@{ Version = 1; Path = $target; Recurse = [bool]$Recurse; Exclude = @($Exclude) }
        $bytes = [System.Text.Encoding]::UTF8.GetBytes(($data | ConvertTo-Json))
        $configStream.Write($bytes, 0, $bytes.Length)
        $configStream.Flush($true)
    } finally { $configStream.Dispose() }
    $taskAction = New-ScheduledTaskAction -Execute $executable -Argument $arguments
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
    # No -Force: a task created concurrently must not be replaced.
    Register-ScheduledTask -TaskName $TaskName -TaskPath '\' -Action $taskAction -Trigger $trigger -Principal $principal -Settings $settings -Description $marker
}
