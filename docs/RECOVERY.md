# Try safely and recover

From the repository root in PowerShell, create a disposable fixture:

```powershell
$demo = Join-Path ([IO.Path]::GetTempPath()) ('dotfolder-demo-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path "$demo/.example" -Force
$manifest = Join-Path $demo 'dotfolders-demo.json'
./scripts/dotfiles/Hide-DotFolders.ps1 -Path $demo -ManifestPath $manifest -WhatIf
./scripts/dotfiles/Hide-DotFolders.ps1 -Path $demo -ManifestPath $manifest
./scripts/dotfiles/Hide-DotFolders.ps1 -RestoreManifest $manifest -WhatIf
./scripts/dotfiles/Hide-DotFolders.ps1 -RestoreManifest $manifest
```

Expected summaries: preview 1, changed 1, preview 1, changed 1. Preview does not
create a manifest or lock. The real folder `.example` ends with its original
visibility. This example never scans your profile.

The summary contains Changed, Skipped, Previewed and Failed. Skipped counts
visited directories only; excluded subtrees are not traversed. Previewed also
includes changes declined at a confirmation prompt. Errors terminate with a
nonzero process result when invoked with `powershell/pwsh -File`.

Recovery validates the whole manifest before changing attributes. Inspect its
paths first. Entries must still be ordinary directories beneath its recorded
root, with no junction/symlink ancestors. A missing folder blocks preflight;
preserve the original manifest and inspect why it disappeared before editing a
copy for recovery. Recovery clears Hidden only and retains all other attributes.
It cannot detect a replacement directory or an intentional later visibility change.

Manifest writes use flushed temporary files and atomic replacement. An exclusive
`.lock` prevents runs from sharing one manifest. Keep recovery files outside Git.
After a killed process a lock can remain: verify no run is active, preserve the
manifest, then remove only that stale lock. Do not remove a lock during execution.
Do not run overlapping operations on the same tree even with different manifests.
Power-loss durability and hostile concurrent filesystem changes are outside scope.

## Optional sign-in task

```powershell
./scripts/dotfiles/Manage-DotFoldersTask.ps1 -Action Install -Path 'D:/Projects' -WhatIf
./scripts/dotfiles/Manage-DotFoldersTask.ps1 -Action Install -Path 'D:/Projects'
./scripts/dotfiles/Manage-DotFoldersTask.ps1 -Action Status
./scripts/dotfiles/Manage-DotFoldersTask.ps1 -Action Uninstall -WhatIf
./scripts/dotfiles/Manage-DotFoldersTask.ps1 -Action Uninstall
```

The default name is `HideDotFolders-Toolkit`; existing tasks, including a task
named `HideDotFolders`, are not replaced. Installation uses the current user's
interactive sign-in and limited privileges. Recursion is opt-in. Concurrent runs
of this task are skipped. Commands refer to the current checkout, so keep it at a
stable path. Configuration and manifests live in
`%LOCALAPPDATA%/WindowsAutomationToolkit` by default and survive uninstall.

Installation does not change execution policy. Your chosen PowerShell host must
already permit these scripts (for example through your normal signed-script
policy). `-PowerShellPath` selects another installed host. Status shows the last
task result. A failed install may leave its configuration for inspection; archive
that file or choose another state directory before retrying. To change settings,
uninstall, archive the old configuration, then install again.

Automated scheduler tests use mocks and execute the runner against a temporary
fixture; they do not register a real scheduled task.
