# flutter_sweeper 🧹

[![pub package](https://img.shields.io/pub/v/flutter_sweeper.svg)](https://pub.dev/packages/flutter_sweeper)
[![pub points](https://img.shields.io/pub/points/flutter_sweeper)](https://pub.dev/packages/flutter_sweeper/score)
[![CI](https://github.com/mehedidevv/flutter_sweeper/actions/workflows/ci.yml/badge.svg)](https://github.com/mehedidevv/flutter_sweeper/actions/workflows/ci.yml)
[![Dart SDK](https://img.shields.io/badge/dart-%3E%3D3.0.0-blue.svg)](https://dart.dev)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)
[![style: lints](https://img.shields.io/badge/style-lints-4BC0F5.svg)](https://pub.dev/packages/lints)

An interactive command-line tool that finds **unused assets**, **unreferenced
Dart files** and **unused classes, functions and methods** in a Flutter
project, then walks you through them **one by one** so you can **Keep** or
**Delete** each one.

```text
🧹 flutter_sweeper v1.0.0
Project: /Users/me/code/shop_app

✓ Parsed 214 Dart files
✓ Scanned assets: 7 unused
✓ Scanned Dart files: 3 unused
✓ Scanned classes, functions & methods: 11 unused

── Class · 12/21 ──────────────────────────────
  Name     PromoBannerV1
  Location lib/widgets/promo_banner_v1.dart:14
  Size     2.3 KB
  Reason   No references outside its own declaration
     14 │ class PromoBannerV1 extends StatelessWidget {
     15 │   const PromoBannerV1({super.key, required this.offer});
? What should flutter_sweeper do?
❯ Keep
  Delete
  Delete all remaining
  Skip all / Quit
```

## Features

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
- **You decide.** You choose Keep / Delete / Delete all remaining /
  Skip all for each item. `--dry-run` only prints the report.

## Installation

```sh
dart pub global activate flutter_sweeper
```

Make sure the pub cache `bin` folder is on your `PATH`, then use either
executable:

```sh
fsweep --help
flutter_sweeper --help
```

## Usage

Run it from the root of a Flutter project (the folder with `pubspec.yaml`):

```sh
fsweep                                 # interactive review
fsweep --dry-run                       # report only, nothing is deleted
fsweep --assets-only                   # only assets
fsweep --code-only                     # only Dart files and declarations
fsweep --code-only --no-methods        # skip method-level findings
fsweep -p ../other_app                 # scan another project
fsweep -e "lib/legacy/**" -e "assets/legal/**"
```

| Option | Abbr | Description |
| --- | --- | --- |
| `--path <dir>` | `-p` | Project root to scan (default: current folder). |
| `--assets-only` | | Only look for unused assets. |
| `--code-only` | | Only look for unused Dart files and declarations. |
| `--dry-run` | `-n` | Print the report and exit without deleting. |
| `--exclude <glob>` | `-e` | Never report matching paths. Repeatable. |
| `--[no-]methods` | | Report unused methods inside used classes (default on). |
| `--verbose` | `-v` | Diagnostic output. |
| `--version` | | Print the version. |
| `--help` | `-h` | Show usage. |

### Interactive choices

| Choice | Effect |
| --- | --- |
| **Keep** | Leave the item and move on to the next one. |
| **Delete** | Delete the file or remove the declaration now. |
| **Delete all remaining** | After a confirmation, delete this and every remaining item. |
| **Skip all / Quit** | Stop and leave everything that is left. |

When the terminal is not interactive (CI, piped output), flutter_sweeper only
prints the report.

## Configuration

Create an optional `flutter_sweeper.yaml` next to `pubspec.yaml`:

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
// flutter_sweeper:keep
void calledFromNativeSide() {}

@pragma('vm:entry-point') // Also protected automatically.
void backgroundHandler() {}
```

Declarations annotated with `@protected` are never reported either.

Put `// flutter_sweeper:ignore_file` anywhere in a file to exclude all of its
declarations, and the file itself, from the report.

## How it works

1. **Parse once.** Every `.dart` file in `lib/`, `test/`, `bin/`, `tool/`,
   `integration_test/` and `test_driver/` is parsed with
   `package:analyzer`.
2. **Assets.** Each candidate counts as used when its full path, its file name
   or its flutter_gen getter appears in a Dart source or a config value.
3. **Files.** A breadth-first walk follows `import`/`export`/`part` (including
   conditional imports) from the entry points. Packages without a `main`
   treat every public library directly under `lib/` as an entry point.
4. **Declarations.** For each class, mixin, enum, typedef, top-level function
   and method in reportable `lib/` files, flutter_sweeper looks for the name
   among the identifier tokens of *all* project files, ignoring occurrences
   inside the declaration itself.

Generated files (`*.g.dart`, `*.freezed.dart`, `*.gr.dart`, `*.config.dart`,
`*.mocks.dart`, `*.gen.dart`, protobuf output, `app_localizations*.dart`,
`lib/generated/**`) are never reported. They still count as references.

## Limitations

flutter_sweeper is conservative: when in doubt it treats something as used.
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
  `// flutter_sweeper:keep` or the `keep:` list.
- **Published packages.** Public API under `lib/` may be used by other
  packages. Review findings carefully, or exclude `lib/` and only sweep
  `lib/src/`.

## Recommended workflow

```sh
git status                 # start from a clean working tree
fsweep --dry-run           # look at the report first
fsweep                     # review and delete
dart fix --apply           # remove imports that became unused
flutter analyze && flutter test
git diff                   # review, then commit
```

flutter_sweeper warns you before it deletes anything in a project that is not
under git.

## Programmatic use

```dart
import 'package:flutter_sweeper/flutter_sweeper.dart';

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
