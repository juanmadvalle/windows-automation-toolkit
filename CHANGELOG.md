# Changelog

## 0.2.0

- Preflight all recovery paths and reject junction/symlink ancestors.
- Flush and atomically replace recovery records, with an exclusive per-record lock.
- Report changed, skipped, previewed and failed counts; propagate failure to callers.
- Add optional limited-user task install/status/uninstall commands without replacing
  existing tasks; preserve configuration and recovery files on uninstall.
- Test PowerShell 5.1 and 7, recovery failures, lock contention, junctions, process
  status and scheduler behavior (mocked), with a disposable walkthrough.
