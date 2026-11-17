# .agent — Project knowledge base for flutter_sweeper

This folder is the single source of truth for humans **and AI coding agents**
working on `flutter_sweeper`. Read this file first, then open the document
that matches your task.

| File | Read it when you need to… |
| --- | --- |
| [PRD.md](PRD.md) | Understand *what* the product is, who it is for, and its requirements. |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Understand *how* it works: layers, data flow, algorithms, design decisions. |
| [CODEBASE_MAP.md](CODEBASE_MAP.md) | Find a file / class quickly and know what it owns. |
| [GUIDELINES.md](GUIDELINES.md) | Write code: conventions, style, rules for agents, do's and don'ts. |
| [TESTING.md](TESTING.md) | Run, write or fix tests; fixture layout; verification checklist. |
| [RELEASE.md](RELEASE.md) | Bump the version and publish to pub.dev. |
| [KNOWN_ISSUES.md](KNOWN_ISSUES.md) | See current bugs, tech debt, limitations and the roadmap. |

## Project at a glance

- **What:** A Dart CLI (`fsweep` / `flutter_sweeper`) that finds unused
  **assets**, unreferenced **Dart files**, and unused **classes, mixins,
  enums, typedefs, functions and methods** in a Flutter project, then lets
  the user **Keep / Delete** each finding interactively.
- **Language / runtime:** Dart `>=3.0.0 <4.0.0` (pure Dart, no Flutter SDK
  needed to run or test).
- **Key dependencies:** `analyzer` 6.x–14.x (AST parsing), `args` (CLI), `mason_logger`
  (terminal UI), `glob`, `path`, `yaml`.
- **Version:** `1.0.0` (in `pubspec.yaml` **and** `lib/src/version.dart`).
- **Entry point:** `bin/flutter_sweeper.dart` → `SweeperCommandRunner.run`.
- **Public API:** `lib/flutter_sweeper.dart` (barrel export).

## Quick commands

```sh
dart pub get
dart format .
dart analyze
dart test
dart run bin/flutter_sweeper.dart --help
dart run bin/flutter_sweeper.dart -p /path/to/flutter_app --dry-run
```

## Current health (2026-11-17, Dart 3.11.5, analyzer 14.5.0)

- `dart format`: clean. `dart analyze --fatal-infos`: no issues.
- `dart test`: 24/24 passing.
- `dart pub publish --dry-run`: 0 warnings.
- Repository: https://github.com/mehedidevv/flutter_sweeper (its own git repo).
- pub.dev: https://pub.dev/packages/flutter_sweeper. Release flow in
  [RELEASE.md](RELEASE.md).

## Keeping these docs current

When you change behaviour, flags, config keys, file layout or the public API,
update the matching document(s) here **in the same change**, as well as the
user-facing `README.md` and `CHANGELOG.md`.
