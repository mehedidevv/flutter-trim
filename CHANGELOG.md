# Changelog

## 1.1.1

- Documentation: a "What's new" section and a reorganised feature list in
  the README, a clearer package description. No code changes.

## 1.1.0 — Undo and restore

Deleting is no longer final. Every deletion can be brought back.

### ↺ Undo during the review
- New **Undo last delete** choice in the menu. It appears as soon as
  something was deleted and names the item it will bring back. Choose it
  again to step further back.
- An undone item counts as kept, and the session summary shows how many
  were undone.

### 🛟 Restore later
- `ftrim --restore` brings back everything deleted in the most recent
  session, newest first, so several edits of the same file unwind exactly.
  Run it again to restore an older session.

### 💾 Automatic backups
- Before a file is deleted or a declaration is removed, the original is
  copied to `.flutter_trim/backups/<session>/` in the project root. If the
  backup cannot be written, nothing is deleted.
- The backup folder is never scanned. Add `.flutter_trim/` to `.gitignore`.
- `--no-backup` turns backups off. The "not under git" confirmation is now
  only shown in that case.

### API
- New: `BackupStore`, `BackupEntry`, `backupDirName`,
  `FileCleaner(backup:)`, `CleanResult.backupId`,
  `PromptDecision.undo`, `TrimStats.restored` / `backedUp`.

## 1.0.0

First release under the name `flutter_trim`. It continues
[`flutter_sweeper`](https://pub.dev/packages/flutter_sweeper) 1.0.0, which is
now discontinued.

### Accuracy on large projects
- Import URIs are percent-decoded, so folders with spaces
  (`package:app/common%20widget/x.dart`) are followed. Previously every file
  in such a folder was reported as unused.
- Imports whose letter case differs from the file on disk
  (`gatewayController.dart` for `gateWayController.dart`) are resolved, as
  they are on macOS and Windows. Previously such files, and everything only
  they imported, were reported as unused.
- Source files with invalid UTF-8 are read leniently instead of being skipped,
  so their references are never lost. Unreadable files now produce a visible
  warning.
- Verified on three production apps (400–600 Dart files each): 0 false
  positives across 134 findings.

### New interface
- Banner, run settings, a summary table and per-category tables that adapt to
  the terminal width and keep file names visible.
- Each finding is shown as a card with a code preview, a progress bar and
  running counts.
- Session summary with suggested next steps.

### New options
- `--json` prints a machine-readable report.
- `--fail-on-findings` exits with code 1 when anything unused is found.

### Renamed
- Executables `ftrim` / `flutter_trim` (were `fsweep` / `flutter_sweeper`).
- Config file `flutter_trim.yaml`; markers `// flutter_trim:keep` and
  `// flutter_trim:ignore_file`.
- Library `package:flutter_trim/flutter_trim.dart`; `SweepItem` is now
  `TrimItem`, `SweeperConfig` is `TrimConfig`, `SweeperCommandRunner` is
  `TrimCommandRunner`, `SweeperException` is `TrimException`,
  `SweepReporter` / `SweepStats` are `TrimReporter` / `TrimStats`.

### Carried over from flutter_sweeper 1.0.0
- Unused asset, unreferenced Dart file and unused declaration detection.
- Safe declaration removal that refuses edits adding syntax errors.
- Works with `package:analyzer` 6.x through 14.x (Dart 3.0 to the latest SDK).
