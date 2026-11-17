# .agent — Project knowledge base for flutter_trim

This folder is the single source of truth for humans **and AI coding agents**
working on `flutter_trim` (formerly `flutter_sweeper`). Read this file first,
then open the document that matches your task.

| File | Read it when you need to… |
| --- | --- |
| [PRD.md](PRD.md) | Understand *what* the product is, who it is for, and its requirements. |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Understand *how* it works: layers, data flow, algorithms, design decisions. |
| [CODEBASE_MAP.md](CODEBASE_MAP.md) | Find a file / class quickly and know what it owns. |
| [GUIDELINES.md](GUIDELINES.md) | Write code: conventions, style, rules for agents, do's and don'ts. |
| [TESTING.md](TESTING.md) | Run, write or fix tests; fixture layout; real-project accuracy check. |
| [RELEASE.md](RELEASE.md) | Bump the version and publish to pub.dev. |
| [KNOWN_ISSUES.md](KNOWN_ISSUES.md) | See current bugs, tech debt, limitations and the roadmap. |

## Project at a glance

- **What:** A Dart CLI (`ftrim` / `flutter_trim`) that finds unused
  **assets**, unreferenced **Dart files**, and unused **classes, mixins,
  enums, typedefs, functions and methods** in a Flutter project, then lets
  the user **Keep / Delete** each finding interactively.
- **Language / runtime:** Dart `>=3.0.0 <4.0.0` (pure Dart, no Flutter SDK
  needed to run or test).
- **Key dependencies:** `analyzer` 6.x–14.x (AST parsing), `args` (CLI),
  `mason_logger` (spinners, menus), `glob`, `path`, `yaml`.
- **Version:** `1.0.0` (in `pubspec.yaml` **and** `lib/src/version.dart`).
- **Entry point:** `bin/flutter_trim.dart` → `TrimCommandRunner.run`.
- **Public API:** `lib/flutter_trim.dart` (barrel export).

## Quick commands

```sh
dart pub get
dart format .
dart analyze --fatal-infos
dart test
dart run bin/flutter_trim.dart --help
dart run bin/flutter_trim.dart -p /path/to/flutter_app --dry-run
dart run bin/flutter_trim.dart -p /path/to/flutter_app --json
```

## Current health (2026-11-17, Dart 3.11.5, analyzer 14.5.0)

- `dart format`: clean. `dart analyze --fatal-infos`: no issues.
- `dart test`: 32/32 passing.
- Real-project accuracy: 0 false positives across 134 findings in three apps
  with 400–600 Dart files (see [TESTING.md](TESTING.md#real-project-accuracy-check)).
- Repository: https://github.com/mehedidevv/flutter-trim
- pub.dev: https://pub.dev/packages/flutter_trim. The old package
  `flutter_sweeper` is discontinued in favour of it.

## Keeping these docs current

When you change behaviour, flags, config keys, file layout or the public API,
update the matching document(s) here **in the same change**, as well as the
user-facing `README.md` and `CHANGELOG.md`.
