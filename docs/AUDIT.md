# Hidden folder audit

Run from the repository root:

```powershell
./scripts/dotfiles/Audit-DotFolders.ps1 -Path 'D:/Projects' -OutputDirectory 'D:/AuditReports' -WhatIf
./scripts/dotfiles/Audit-DotFolders.ps1 -Path 'D:/Projects' -OutputDirectory 'D:/AuditReports' -MaxDepth 3 -Exclude node_modules,.git
```

Both paths are mandatory (`-Root` is an alias for `-Path`). The output must be
outside the scanned tree. The default depth is 1: immediate children only. The
root itself is not a report row. At depth 3, grandchildren and great-grandchildren
are included; deeper trees are not enumerated. Allowed depths are 1 through 100.
Exclusions are exact directory names, case-insensitive, and prune complete
subtrees including their report rows. Wildcards and paths are rejected.

The script traverses ordinary directories to find dot-prefixed or Hidden
directories. It never reads file contents, changes attributes, or deletes files.
Reparse points are not followed; matching links are reported as uninspected.
Linked roots, output paths and their ancestors are rejected. Keep the tree idle:
hostile concurrent filesystem changes are outside the supported use case.

`-WhatIf` scans and returns counts but creates no output. A normal run creates a
unique `dotfolder-audit-<id>` folder with `report.html`, `report.csv`, and
`report.json`. Earlier reports are not overwritten. JSON contains rows, scan
errors and scope/counts. CSV protects formula-like text with an apostrophe; JSON
retains the original values. HTML encodes all dynamic text and loads no external
resources. Empty results still produce valid files and a CSV header.

Access failures are recorded and other queued directories continue. The report
is marked incomplete and the command throws after writing it, giving a nonzero
result under `powershell/pwsh -File`. Output-writing errors also terminate; a
partially written report directory may remain. Depth/exclusion omissions are
intentional and are not scan errors: “complete” means within the requested scope.

Recommendations are name-based heuristics, not proof that a folder is unused or
safe to delete. Sensitive and application parent paths take precedence over cache
names. The tool does not measure reclaimable space or detect application use.

Reports contain personal paths. Generated `dotfolder-audit-*` folders are ignored
by Git, even when copied into this repository; renamed exports are not covered.
Keep reports private and review them before sharing. No real audit report is
included in this repository. The tests use only synthetic temporary directories.
