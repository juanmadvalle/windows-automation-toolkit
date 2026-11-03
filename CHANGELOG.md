# Changelog

## Unreleased

- Record each hidden folder's creation time and skip it on restore if the
  directory was replaced since the run (older manifests still restore).
- Add a read-only hidden-folder audit with mandatory paths, exact exclusions,
  depth limits, non-overwriting HTML/CSV/JSON reports and explicit scan errors.
- Protect spreadsheet cells, encode HTML, ignore generated reports, and test
  synthetic trees, inaccessible directories, empty results and junctions.

## 0.2.0

- Preflight all recovery paths and reject junction/symlink ancestors.
- Flush and atomically replace recovery records, with an exclusive per-record lock.
- Report changed, skipped, previewed and failed counts; propagate failure to callers.
- Add optional limited-user task install/status/uninstall commands without replacing
  existing tasks; preserve configuration and recovery files on uninstall.
- Test PowerShell 5.1 and 7, recovery failures, lock contention, junctions, process
  status and scheduler behavior (mocked), with a disposable walkthrough.
