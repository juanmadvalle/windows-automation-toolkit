# Windows automation toolkit

Small personal Windows utilities. No scheduled task is installed by this repository.

## Hide dot folders

Requires Windows PowerShell 5.1 or PowerShell 7 on Windows. Only directories whose names start with `.` receive the Hidden attribute. Existing attributes and already-hidden folders are preserved. Files such as `.gitignore` are not changed. Hidden is a display preference, not an access restriction or sync-exclusion policy.

```powershell
# Preview immediate children only.
./scripts/dotfiles/Hide-DotFolders.ps1 -Path $env:USERPROFILE -WhatIf

# Explicit recursion; excluded names prune their entire subtree.
./scripts/dotfiles/Hide-DotFolders.ps1 -Path 'D:/Projects' -Recurse -Exclude node_modules,.git -WhatIf

# Apply and save recovery intent before each change.
./scripts/dotfiles/Hide-DotFolders.ps1 -Path 'D:/Projects' -ManifestPath './dotfolders-run.json'

# Preview restoration, then remove -WhatIf to restore.
./scripts/dotfiles/Hide-DotFolders.ps1 -RestoreManifest './dotfolders-run.json' -WhatIf
```

The root itself is not hidden. Reparse points (including junctions) are skipped. Exclusions are exact directory names, compared case-insensitively. Errors are reported; other accessible folders continue. A manifest is created only when a change is approved; `-WhatIf` does not create it. Manifest paths contain personal information and are ignored by Git.

Restore clears only Hidden from recorded paths, retaining other attributes. It also covers a run interrupted between recording intent and applying the attribute. It cannot distinguish a later user change or a replacement directory at the same path: inspect manifests before restoring. Keep the folder tree idle during a run; hostile concurrent filesystem changes are outside scope.

The recovered original and existing deployed script/task are untouched. Recursion is now opt-in, a target path is mandatory, and there is no silent error suppression.

## Validation

```powershell
pwsh -NoProfile -File ./tests/Hide-DotFolders.Tests.ps1
```

The integration check creates its own temporary folders; it never scans a real user profile. PowerShell 5.1 compatibility is intended but must be verified separately if it was not used for the recorded check.
