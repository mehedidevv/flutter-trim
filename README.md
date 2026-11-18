# flutter_trim ✂️

[![pub package](https://img.shields.io/pub/v/flutter_trim.svg)](https://pub.dev/packages/flutter_trim)
[![pub points](https://img.shields.io/pub/points/flutter_trim)](https://pub.dev/packages/flutter_trim/score)
[![CI](https://github.com/mehedidevv/flutter-trim/actions/workflows/ci.yml/badge.svg)](https://github.com/mehedidevv/flutter-trim/actions/workflows/ci.yml)
[![Dart SDK](https://img.shields.io/badge/dart-%3E%3D3.0.0-blue.svg)](https://dart.dev)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)

An interactive command-line tool that finds **unused assets**, **unreferenced
Dart files** and **unused classes, functions and methods** in a Flutter
project, then walks you through them **one by one** so you can **Keep** or
**Delete** each one.

```text
  ╭─ Class ────────────────────────────────────────────────── 12 / 21 ─╮
  │ PromoBannerV1                                                      │
  │ lib/widgets/promo_banner_v1.dart:14  ·  2.3 KB                     │
  │ No references outside its own declaration                          │
  ├────────────────────────────────────────────────────────────────────┤
  │    14 │ class PromoBannerV1 extends StatelessWidget {              │
  │    15 │   const PromoBannerV1({super.key, required this.offer});   │
  │    16 │                                                            │
  │    17 │   final Offer offer;                                       │
  ╰────────────────────────────────────────────────────────────────────╯
  ▰▰▰▰▰▰▰▰▰▰▰▱▱▱▱▱▱▱▱▱ 4 deleted · 7 kept
? What do you want to do?
❯ Keep
  Delete
  Delete all remaining
  Quit and keep the rest
```

> Formerly published as `flutter_sweeper`. The package was renamed and its
> import resolution rewritten for large projects; see the
> [changelog](CHANGELOG.md).

## Features

- **Built for large apps.** Tested on real Flutter apps with 400–600 Dart
  files. Import paths with spaces (`common%20widget/`) and imports whose
  letter case differs from the file name (`gatewayController.dart` for
  `gateWayController.dart`, which macOS and Windows accept) are resolved
  correctly, so used files are never reported.
- **Unused assets.** Reads `flutter: assets:` from `pubspec.yaml`, expands
  directory entries the way Flutter does (including `2.0x/` and `3.0x/`
  variants), also finds files in `assets/` that were never declared, and
  checks them against every Dart source plus tool configs such as
  `flutter_launcher_icons`. Projects using flutter_gen are matched by getter
  name (`Assets.images.logo`).
- **Unreferenced Dart files.** Builds an import graph from your entry points
  (`main*.dart`, `test/`, `bin/`, ...) through `import`, `export`, `part` and
  conditional imports. Files that cannot be reached are reported, and their
  `part` files (`*.g.dart`, `*.freezed.dart`) are deleted with them.
- **Unused classes, mixins, enums, typedefs, functions and methods.** Uses the
  official `analyzer` AST instead of regular expressions, so comments, strings
  and self references do not confuse it.
- **Safe removal.** Declarations are cut out together with their doc comments
  and annotations, and the file is parsed again before anything is written.
  If the edit would add a syntax error, the file is left untouched.
- **You decide.** Keep / Delete / Delete all remaining / Quit for each item,
  with a code preview. `--dry-run` only prints the report.
- **Undo.** Everything is backed up before it is deleted. Undo the last
  delete during the review, or bring back a whole session with
  `ftrim --restore`.
- **CI ready.** `--json` for machine-readable output and
  `--fail-on-findings` to fail a build when something is unused.

## Installation

```sh
dart pub global activate flutter_trim
```

Make sure the pub cache `bin` folder is on your `PATH`, then use either
executable:

```sh
ftrim --help
flutter_trim --help
```

## Usage

Run it from the root of a Flutter project (the folder with `pubspec.yaml`):

```sh
ftrim                                  # interactive review
ftrim --dry-run                        # report only, nothing is deleted
ftrim --assets-only                    # only assets
ftrim --code-only                      # only Dart files and declarations
ftrim --code-only --no-methods         # skip method-level findings
ftrim -p ../other_app                  # scan another project
ftrim -e "lib/legacy/**" -e "assets/legal/**"
ftrim --json > report.json             # machine-readable report
ftrim -n --fail-on-findings            # exit code 1 if anything is unused
ftrim --restore                        # undo the deletions of the last session
```

| Option | Abbr | Description |
| --- | --- | --- |
| `--path <dir>` | `-p` | Project root to scan (default: current folder). |
| `--assets-only` | | Only look for unused assets. |
| `--code-only` | | Only look for unused Dart files and declarations. |
| `--dry-run` | `-n` | Print the report and exit without deleting. |
| `--exclude <glob>` | `-e` | Never report matching paths. Repeatable. |
| `--[no-]methods` | | Report unused methods inside used classes (default on). |
| `--json` | | Print the findings as JSON (implies `--dry-run`). |
| `--fail-on-findings` | | Exit with code 1 when anything unused is found. |
| `--[no-]backup` | | Back up everything before deleting it, so it can be undone (default on). |
| `--restore` | | Bring back everything deleted in the most recent session, then exit. Run it again to undo older sessions. |
| `--verbose` | `-v` | Diagnostic output. |
| `--version` | | Print the version. |
| `--help` | `-h` | Show usage. |

### Interactive choices

| Choice | Effect |
| --- | --- |
| **Keep** | Leave the item and move on to the next one. |
| **Delete** | Delete the file or remove the declaration now. |
| **Delete all remaining** | After a confirmation, delete this and every remaining item. |
| **Undo last delete** | Put back the item deleted most recently (shown once something was deleted). It then counts as kept. |
| **Quit and keep the rest** | Stop and leave everything that is left. |

### Undo and restore

Before a file is deleted or a declaration is removed, flutter_trim copies
the original into `.flutter_trim/backups/<session>/` in the project root.
Each deletion can be undone during the review with **Undo last delete**, and
`ftrim --restore` brings back every deletion of the most recent session,
newest first. Add `.flutter_trim/` to your `.gitignore`. Delete that folder
when you no longer need the backups. Pass `--no-backup` to skip backups.

When the terminal is not interactive (CI, piped output), flutter_trim only
prints the report.

### JSON output

```json
{
  "tool": "flutter_trim",
  "version": "1.0.0",
  "project": "/path/to/app",
  "summary": { "total": 3, "sizeBytes": 4210, "asset": 1, "file": 1, "declaration": 1 },
  "items": [
    { "type": "declaration", "kind": "method", "name": "voteBlog", "parent": "AppUrl",
      "path": "lib/core/network/api_url.dart", "line": 188, "sizeBytes": 83,
      "reason": "Method is never called or torn off anywhere in the project" }
  ]
}
```

## Configuration

Create an optional `flutter_trim.yaml` next to `pubspec.yaml`:

```yaml
# Paths that are never reported (globs, relative to the project root).
exclude:
  - lib/generated/**
  - assets/legal/**

# Extra entry points for the import graph (flavors, isolates, ...).
entry_points:
  - lib/bootstrap/background_worker.dart

# Declarations that must never be reported.
keep:
  - LegacyApiClient
  - onDidReceiveBackgroundNotification

# Folders searched for assets in addition to pubspec declarations.
asset_directories:
  - assets
  - res

# Turn whole scanners on or off.
scan:
  assets: true
  files: true
  code: true
  methods: true
```

CLI `--exclude` globs are added to the ones in the config file, and
`--[no-]methods` overrides `scan.methods`.

### Protecting code inline

```dart
// flutter_trim:keep
void calledFromNativeSide() {}

@pragma('vm:entry-point') // Also protected automatically.
void backgroundHandler() {}
```

Declarations annotated with `@protected` are never reported either.

Put `// flutter_trim:ignore_file` anywhere in a file to exclude all of its
declarations, and the file itself, from the report.

## How it works

1. **Parse once.** Every `.dart` file in `lib/`, `test/`, `bin/`, `tool/`,
   `integration_test/` and `test_driver/` is parsed with
   `package:analyzer`. Files with invalid UTF-8 are still read, so their
   references are never lost.
2. **Assets.** Each candidate counts as used when its full path, its file name
   or its flutter_gen getter appears in a Dart source or a config value.
3. **Files.** A breadth-first walk follows `import`/`export`/`part` (including
   conditional imports) from the entry points. URIs are percent-decoded and
   matched to files case-insensitively when there is no exact match. Packages
   without a `main` treat every public library directly under `lib/` as an
   entry point.
4. **Declarations.** For each class, mixin, enum, typedef, top-level function
   and method in reportable `lib/` files, flutter_trim looks for the name
   among the identifier tokens of *all* project files, ignoring occurrences
   inside the declaration itself.

Generated files (`*.g.dart`, `*.freezed.dart`, `*.gr.dart`, `*.config.dart`,
`*.mocks.dart`, `*.gen.dart`, protobuf output, `app_localizations*.dart`,
`lib/generated/**`) are never reported. They still count as references.

## Limitations

flutter_trim is conservative: when in doubt it treats something as used.
Keep these cases in mind:

- **Name-based matching.** Two declarations with the same name keep each other
  alive, and a method name used anywhere (even on an unrelated type) counts
  as used.
- **Dynamic asset paths** such as `'assets/icons/$name.png'` cannot be
  resolved. The file-name check catches `'$dir/logo.png'`, but not names
  built at runtime.
- **Hand-written asset constant files** (`static const logo = 'assets/...'`)
  make every listed asset look used, even if the constant is not.
- **Code used only by tests** counts as used.
- **Reflection, `dart:mirrors`, platform channels and native callbacks** are
  invisible to static analysis. Protect them with `@pragma('vm:entry-point')`,
  `// flutter_trim:keep` or the `keep:` list.
- **Published packages.** Public API under `lib/` may be used by other
  packages. Review findings carefully, or exclude `lib/` and only trim
  `lib/src/`.

## Recommended workflow

```sh
git status                 # start from a clean working tree
ftrim --dry-run            # look at the report first
ftrim                      # review and delete
dart fix --apply           # remove imports that became unused
flutter analyze && flutter test
git diff                   # review, then commit
```

flutter_trim warns you before it deletes anything in a project that is not
under git.

## Programmatic use

```dart
import 'package:flutter_trim/flutter_trim.dart';

void main() {
  final context = ProjectContext.load('path/to/app');
  final unusedFiles = FileScanner(context).scan();
  final unusedCode = CodeScanner(
    context,
    skipFiles: {for (final item in unusedFiles) item.path},
  ).scan();

  for (final item in [...AssetScanner(context).scan(), ...unusedFiles, ...unusedCode]) {
    print('${item.typeLabel.padRight(10)} ${item.location}  ${formatBytes(item.sizeBytes)}');
  }
}
```

## Contributing

Issues and pull requests are welcome, especially reports of false positives.
See [CONTRIBUTING.md](CONTRIBUTING.md) for the development setup and checks
to run before opening a PR.

## License

MIT. See [LICENSE](LICENSE).
