# Windows automation toolkit

Small personal Windows utilities. Sign-in automation is optional and requires an explicit install command.

## Audit hidden folders

`scripts/dotfiles/Audit-DotFolders.ps1` reports hidden and dot-prefixed directories without modifying the scanned tree. It requires explicit input/output paths, defaults to immediate children, supports exclusions and bounded depth, and exports HTML, protected CSV and JSON. See the [audit guide](docs/AUDIT.md) for examples, privacy and incomplete-scan handling.

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

The root itself is not hidden. Reparse points (including junctions) are skipped; linked roots and ancestor paths are rejected. Exclusions are exact directory names, compared case-insensitively. Folder errors are reported and other accessible folders continue; validation and persistence errors stop the run. Failures produce a nonzero process result. A manifest is created only when a change is approved; `-WhatIf` does not create it. Manifest paths contain personal information and are ignored by Git.

Each run returns a summary with Changed, Skipped, Previewed and Failed counts. Manifests are exclusively locked, flushed and atomically replaced before each change. Recovery validates the full record before altering folders.

Restore clears only Hidden from recorded paths, retaining other attributes. It also covers a run interrupted between recording intent and applying the attribute. It cannot distinguish a later user change or a replacement directory at the same path: inspect manifests before restoring. Keep the folder tree idle during a run; hostile concurrent filesystem changes are outside scope.

The recovered original and existing deployed script/task are untouched. Recursion is now opt-in, a target path is mandatory, and there is no silent error suppression.

## Validation

```powershell
pwsh -NoProfile -File ./tests/Hide-DotFolders.Tests.ps1
pwsh -NoProfile -File ./tests/Safety.Tests.ps1
pwsh -NoProfile -File ./tests/Task.Tests.ps1
pwsh -NoProfile -File ./tests/Audit.Tests.ps1
```

The checks create temporary folders and never scan a real user profile. They run on Windows PowerShell 5.1 and PowerShell 7 in CI. Scheduler commands are mocked, so tests do not install real tasks. The recovery checks create a temporary junction and require permission to do so.

See the [disposable example, recovery guide and task commands](docs/RECOVERY.md) and [changelog](CHANGELOG.md).

## License

Licensed under the [MIT License](LICENSE).
