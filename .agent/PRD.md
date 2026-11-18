# Product Requirements Document: flutter_trim

| | |
| --- | --- |
| Product | flutter_trim (`ftrim`), formerly flutter_sweeper |
| Type | Dart command-line tool, published on pub.dev |
| Version covered | 1.0.0 |
| Status | Implemented (initial release); pre-publish |
| License | MIT |

---

## 1. Problem

Flutter projects build up dead weight over time:

- **Assets** (images, JSON, fonts, raw files) that no code uses anymore. They
  bloat the app bundle.
- **Dart files** that nothing imports after refactors.
- **Classes, functions and methods** that nothing calls.

Existing options are weak:
- `dart analyze` only flags *private* unused members and unused imports.
- Regex-based scripts give false positives from comments and strings, and
  they miss conditional imports and `part` files.
- Bulk-delete tools are risky because they don't let developers review each
  item.

## 2. Goal

Give Flutter developers a **safe, interactive, conservative** tool that finds
dead code and dead assets and lets them remove each item **one at a time**,
without breaking the build.

### Non-goals
- Full semantic (type-resolved) dead-code analysis.
- Automatically fixing imports after deletions (we tell the user to run
  `dart fix --apply`).
- Analyzing dependencies or other packages in a monorepo.
- A GUI or IDE plugin (for now).

## 3. Target users

| Persona | Need |
| --- | --- |
| Flutter app developer | Shrink the APK/IPA and clean up after refactors. |
| Tech lead / reviewer | Get a dry-run report of dead code before a cleanup sprint. |
| CI maintainer | Get a non-interactive report (the tool auto-detects a non-TTY). |
| Tool author | Embed scanners programmatically (exported API). |

## 4. Product principles

1. **Conservative over clever.** When in doubt, treat the item as *used*.
   False negatives are acceptable; false positives are not.
2. **The user decides.** Nothing is deleted without an explicit choice,
   except with "Delete all remaining" plus a confirmation.
3. **Never break the file.** Declaration removal is re-parsed, and the tool
   aborts if the removal would add syntax errors.
4. **Zero config to start.** Sensible defaults, with an optional YAML config
   for power users.
5. **Fast.** Each Dart file is parsed once and shared by all scanners.

## 5. Functional requirements

### FR-1 Asset scanning
- FR-1.1 Read `flutter: assets:` from `pubspec.yaml`, including string
  entries and Flutter 3.19+ map entries (`- path: ...`). Skip `packages/...`.
- FR-1.2 Expand directory entries the way Flutter does: direct files, plus
  resolution variants (`2.0x/`, `3.0x/`), but not other subfolders.
- FR-1.3 Also walk the configured `asset_directories` (default `assets/`)
  recursively to find **undeclared** files.
- FR-1.4 Exclude font files declared under `flutter: fonts:`.
- FR-1.5 Ignore OS junk (`.DS_Store`, `Thumbs.db`, `desktop.ini`, `.gitkeep`,
  `.keep`), dotfiles, hidden folders and `.dart` files.
- FR-1.6 Count an asset as used if any of the following appear in Dart
  sources, non-asset pubspec values, or root-level `*.yaml`/`*.yml` configs
  (except `pubspec.yaml`, `pubspec.lock`, `flutter_trim.yaml`):
  - its full path,
  - its base path (variant folder removed),
  - its file name (with a boundary check),
  - its flutter_gen getter name, when the project uses flutter_gen.
- FR-1.7 Ignore `*.gen.dart` contents in the text corpus, because flutter_gen
  lists every asset.
- FR-1.8 The reason text says whether the asset was declared in pubspec.

### FR-2 Unreferenced Dart files
- FR-2.1 Build an import graph through `import`, `export`, `part` and
  conditional (`if (dart.library.x)`) URIs.
- FR-2.2 Entry points:
  - every Dart file outside `lib/`,
  - `lib/` files that declare top-level `main`,
  - if no `main` exists (a package), every public library outside `lib/src/`,
  - `entry_points` from the config.
- FR-2.3 Resolve `package:<self>/…` and relative URIs only. URIs are
  percent-decoded (`%20` → space), and when no file matches exactly, a file
  whose path differs only by letter case is used (macOS/Windows compile such
  imports).
- FR-2.4 Report only `lib/` files that cannot be reached. Never report
  `part of` files or ignored/generated/excluded files.
- FR-2.5 Attach `part` files as *companions*, deleted together with the
  library, and include their size.

### FR-3 Unused declarations
- FR-3.1 Use `package:analyzer` AST (`parseString`, unresolved).
- FR-3.2 Candidates: top-level classes, class type aliases, mixins, enums,
  typedefs and functions (not getters or setters) in reportable `lib/` files.
- FR-3.3 Methods inside classes, mixins, enums and extensions, unless one of
  these applies:
  - it's an operator, getter, setter, abstract or external member,
  - it has `@override`,
  - it's a conventional framework method (`build`, `initState`, `dispose`,
    `toJson`, `fromJson`, `props`, …),
  - its container has `@pragma`.
- FR-3.4 A declaration is used if its name appears as an identifier token in
  **any** project Dart file (lib, test, bin, tool, integration_test,
  test_driver, including generated files) **outside its own source range**.
- FR-3.5 Never report declarations that:
  - are named `main`,
  - are listed in `keep`,
  - are annotated `@pragma` or `@protected`,
  - have `// flutter_trim:keep` on the line above or in their doc comment.
- FR-3.6 Don't report methods of a container that is already reported unused.
- FR-3.7 Don't report declarations in files that FR-2 already reported.
- FR-3.8 Sort findings by path, then line.

### FR-4 Interactive review
- FR-4.1 Print a grouped table report: assets, then files, then
  declarations, with counts and sizes.
- FR-4.2 For each item, show the type, position (n/N), name, location, size,
  reason, companions, and a 4-line code preview for declarations.
- FR-4.3 Choices: **Keep**, **Delete**, **Delete all remaining** (needs a
  confirmation, default No), **Skip all / Quit**.
- FR-4.4 If the project isn't inside a git repo, warn and ask to continue
  (default No).
- FR-4.5 If the terminal isn't interactive (stdin or stdout isn't a TTY),
  print the report only.
- FR-4.6 The summary shows deleted (with bytes freed), kept, skipped and
  failed counts, plus the failure list. Suggest `dart fix --apply` when Dart
  code was touched.

### FR-5 Safe removal
- FR-5.1 Delete asset/file items and their companions. Report the bytes freed.
- FR-5.2 For declarations, re-parse the file at deletion time, find the node
  by kind/name/parent, and remove its range together with doc comments,
  annotations, leading indentation, the trailing newline and one extra blank
  line.
- FR-5.3 Refuse the edit if the error count after parsing goes up.
- FR-5.4 Fail gracefully (with a reason) if the file or node no longer exists.

### FR-6 CLI
| Flag | Behaviour |
| --- | --- |
| `-p, --path <dir>` | Project root (default `.`); must contain `pubspec.yaml`. |
| `--assets-only` / `--code-only` | Mutually exclusive scope filters. |
| `-n, --dry-run` | Report and exit. |
| `-e, --exclude <glob>` | Repeatable; added to the config excludes. |
| `--[no-]methods` | Overrides `scan.methods`. |
| `-v, --verbose` | Diagnostic output (skipped files, stack traces). |
| `--version`, `-h, --help` | |

| `--json` | Print findings as JSON; implies dry run. |
| `--fail-on-findings` | Exit 1 when anything unused is found. |
| `--[no-]backup` | Back up before deleting (default on). |
| `--restore` | Undo every deletion of the most recent session and exit. |

FR-6.1 Undo: during review, **Undo last delete** restores the most recently
deleted item from its backup (it then counts as kept).

Two executables: `ftrim` and `flutter_trim`.

### FR-7 Configuration (`flutter_trim.yaml`)
Keys: `exclude`, `entry_points`, `keep`, `asset_directories`,
`scan.{assets,files,code,methods}`. Settings may also sit under a top-level
`flutter_trim:` key. A single string is accepted where a list is
expected. Invalid YAML or a non-map root gives exit code 78.

Inline markers: `// flutter_trim:keep`, `// flutter_trim:ignore_file`.

### FR-8 Exit codes (sysexits)
| Code | Meaning |
| --- | --- |
| 0 | Success (including a clean project, dry run, non-interactive run, or user quit) |
| 1 | One or more deletions failed |
| 64 | Usage error |
| 66 | Path missing or no `pubspec.yaml` |
| 70 | Unexpected error |
| 78 | Config error |

### FR-9 Programmatic API
Export `ProjectContext`, `AssetScanner`, `FileScanner`, `CodeScanner`,
`FileCleaner`, `TrimItem` and related types, `TrimConfig`,
`ConfigLoader`, `PathFilter`, `TrimReporter`, `TrimStats`, `formatBytes`,
`TrimCommandRunner`, `InteractivePrompt`, `packageVersion`, and the marker
constants.

## 6. Non-functional requirements

| ID | Requirement |
| --- | --- |
| NFR-1 | Runs on macOS, Linux and Windows. Paths are normalized to `/` for matching. |
| NFR-2 | No Flutter SDK required, because parsing is unresolved. |
| NFR-3 | Each file is parsed once per run. |
| NFR-4 | Generated code (`*.g.dart`, `*.freezed.dart`, `*.gr.dart`, `*.config.dart`, `*.mocks.dart`, `*.gen.dart`, `*.pb*.dart`, `app_localizations*`, `generated_plugin_registrant.dart`, `lib/generated/**`) is never reported but still counts as a reference. |
| NFR-5 | Unreadable files are skipped and logged at verbose level. They don't crash the run. |
| NFR-6 | Colors degrade to plain text when ANSI isn't supported. |
| NFR-7 | `dart analyze` is clean under `package:lints/recommended` plus the project's extra rules. |

## 7. Known product limitations (accepted)
Name-based matching, dynamic asset paths, hand-written asset constant files,
code used only by tests counting as used, reflection and native callbacks,
and public API of published packages. See README "Limitations" and
[KNOWN_ISSUES.md](KNOWN_ISSUES.md).

## 8. Success metrics
- Zero reported regressions where a deletion broke compilation for
  `@override` or framework methods.
- A false-positive rate low enough that users keep using the Delete choice.
- pub.dev score: full points for docs, platforms and analysis.

## 9. Future scope (candidate)
See the roadmap in [KNOWN_ISSUES.md](KNOWN_ISSUES.md#roadmap).
