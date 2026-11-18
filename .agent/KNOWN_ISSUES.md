# Known issues, tech debt and roadmap

Last full scan: 2026-11-17 (Dart SDK 3.11.5, analyzer 14.5.0).

## Bugs

None open.

### Resolved
- **KI-1** (fixed 2026-11-17): the test suite didn't compile because `anyOf`
  was given more than 7 matchers. It's now a loop of `isNot(contains(...))`.
- **KI-2** (fixed 2026-11-17): `require_trailing_commas` infos.
  `dart analyze --fatal-infos` is now clean.
- **KI-3** (fixed 2026-11-17): the code didn't compile with analyzer ≥11,
  which removed `NamedCompilationUnitMember`, `ClassDeclaration.name` and
  `.members`. `DeclarationUtils` now uses version-agnostic APIs, and the
  constraint is `>=6.2.0 <15.0.0`.
- **KI-4** (fixed in flutter_trim 1.0.0): import URIs with `%20` were not
  decoded, so every file in a folder with a space looked unreachable and was
  reported as unused (62 findings in one 397-file app, 8 of them used).
- **KI-5** (fixed in flutter_trim 1.0.0): imports whose letter case differed
  from the file on disk (`gatewayController.dart` vs `gateWayController.dart`)
  were not followed, so used files and everything only they imported were
  reported as unused. One such file had 10 importers.
- **KI-6** (fixed in flutter_trim 1.0.0): a file that failed UTF-8 decoding
  was skipped silently, dropping its references.

## Package history
- `flutter_sweeper` 1.0.0 was the first release. The package continues as
  `flutter_trim`; `flutter_sweeper` is marked discontinued on pub.dev with
  "replaced by flutter_trim" (published versions cannot be deleted).

## Publishing caveats

- If `dart pub publish` fails with `Entry …%20… is not inside …`, pub is
  listing files through a git repository *above* the project and choking on
  the space in the path (`Mehedi Hasan`). The project now has its own git
  repository, which avoids this. If it ever reappears, publish from a path
  without spaces.

## Tech debt

| ID | Item | Notes |
| --- | --- | --- |
| TD-1 | The version is duplicated in `pubspec.yaml` and `version.dart` | Guarded by the test `packageVersion matches pubspec.yaml`. |
| TD-3 | `analyzer` support spans 6.x–14.x | Raise the upper bound for each new analyzer major *after* checking its CHANGELOG for removed AST APIs. CI's weekly run plus the `lowest-dependencies` job catch breakage. |
| TD-4 | `FileCleaner.dryRun` isn't used by the CLI | API-only for now. |
| TD-6 | `AssetScanner._isReferenced` compiles a regex per candidate | Fine for typical apps. |
| TD-7 | No tests for the `InteractivePrompt` decision flow | See TESTING.md "Gaps". Rendering is covered by the width test. |
| TD-11 | Removing the last declaration in a file leaves an import-only file | Mitigated by suggesting `dart fix --apply`. |
| TD-12 | The lowest-SDK (3.0) runtime isn't tested in CI | Dev dependencies (`lints ^6`, `test ^1.25`) need a newer SDK. The `lowest-dependencies` job analyzes `lib/` against the lowest versions instead. |

## Accepted limitations (by design)
Name-based matching, dynamic asset paths, hand-written asset constant files,
code used only by tests, reflection and native callbacks, public API of
published packages, and `@protected` declarations (never reported). All are
documented in the README.

## Roadmap
Done in flutter_trim 1.0.0: `--json`, `--fail-on-findings`.
Done (Unreleased): backups, **Undo last delete**, `--restore`, `--[no-]backup`.

Note: backups are never cleaned up automatically; users delete
`.flutter_trim/` themselves.

1. `--yes` / `--delete-all` for non-interactive cleanup (with a git-clean
   precondition).
2. Unused top-level variables, getters and setters, and extensions as a whole.
3. Unused `pubspec.yaml` dependencies.
4. Unused localization keys (ARB).
5. Optional resolved (type-aware) analysis mode.
6. Monorepo / melos support.
7. Automatically remove imports that became unused after deletion.
8. Baseline file for known findings.
