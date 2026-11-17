# Codebase map

```
flutter-trim/
├── bin/
│   └── flutter_trim.dart           # main(): runs TrimCommandRunner, flushes stdio, exit(code)
├── lib/
│   ├── flutter_trim.dart           # Public barrel export (the programmatic API surface)
│   └── src/
│       ├── version.dart            # packageVersion: keep in sync with pubspec.yaml
│       ├── cli/
│       │   ├── command_runner.dart     # TrimCommandRunner: ArgParser, pipeline, --json, git check, usage
│       │   ├── interactive_prompt.dart # InteractivePrompt + PromptDecision: item cards, menu, deletion
│       │   ├── reporter.dart           # TrimReporter (banner, summary, tables, session summary), TrimStats
│       │   └── ui.dart                 # Ui (boxes, tables, progress bar), paint, formatBytes, ANSI-aware width
│       ├── scanners/
│       │   ├── project_context.dart    # ProjectContext (case-insensitive fileAt), ParsedDartFile, markers
│       │   ├── asset_scanner.dart      # AssetScanner (+ flutterGenName), _AssetDeclarations
│       │   ├── file_scanner.dart       # FileScanner: entry points, resolveUri (%-decoding), import BFS
│       │   ├── code_scanner.dart       # CodeScanner, _Usage, _Candidate
│       │   └── declaration_utils.dart  # DeclarationUtils: shared by CodeScanner & FileCleaner
│       ├── cleaners/
│       │   └── file_cleaner.dart       # FileCleaner, CleanResult, removeRange
│       ├── models/
│       │   └── trim_item.dart          # TrimItem, TrimItemType, DeclarationKind, ExitCodes, TrimException
│       └── utils/
│           └── config_loader.dart      # TrimConfig, ConfigLoader, PathFilter (generated-file rules)
├── test/
│   └── scanner_test.dart           # All tests + createFixture() temp-project builder
├── example/
│   ├── example.dart                # Runnable programmatic example (pub.dev "Example" tab)
│   └── README.md                   # CLI usage examples
├── .github/
│   ├── workflows/ci.yml            # Format, analyze, test (3 OSes × stable/beta), publish dry run, lowest deps
│   ├── workflows/publish.yml       # Tag vX.Y.Z → automated pub.dev publish (OIDC)
│   ├── ISSUE_TEMPLATE/             # Bug / false positive, feature request
│   └── pull_request_template.md
├── CONTRIBUTING.md                 # Dev setup, checks, release steps
├── README.md                       # User docs (pub.dev landing page)
├── CHANGELOG.md                    # Release notes
├── LICENSE                         # MIT
├── analysis_options.yaml           # lints/recommended + strict-casts/raw-types + extra rules
├── pubspec.yaml                    # Package metadata, deps, executables (ftrim, flutter_trim)
├── .gitignore
├── .pubignore                      # Overrides .gitignore for publishing; excludes .agent/, .github/, IDE/build files
└── .agent/                         # This knowledge base
```

## Symbol index

| Symbol | File | Responsibility |
| --- | --- | --- |
| `TrimCommandRunner` | cli/command_runner.dart | CLI entry. `run(args) → Future<int>`. Injectable `Logger` and `interactive`. |
| `InteractivePrompt` | cli/interactive_prompt.dart | Per-item card, Keep/Delete menu, deletion, stats. |
| `PromptDecision` | cli/interactive_prompt.dart | `keep, delete, deleteAll, quit` with labels. |
| `TrimReporter` | cli/reporter.dart | Banner, summary table, detail tables, clean/dry-run messages, session summary. |
| `TrimStats` | cli/reporter.dart | Mutable counters for a session. |
| `Ui` | cli/ui.dart | `box`, `table` (with `shrink` column), `progressBar`; width from the terminal. |
| `paint`, `formatBytes`, `visibleLength`, `fitStart`, `fitEnd` | cli/ui.dart | Formatting helpers (ANSI-aware). |
| `ProjectContext` | scanners/project_context.dart | Root, package name, pubspec, config, filter, parsed files; `fileAt` falls back to a case-insensitive match. |
| `ParsedDartFile` | scanners/project_context.dart | Content, AST, line info, identifier tokens, ignore/partOf flags. |
| `AssetScanner` | scanners/asset_scanner.dart | Unused asset detection. |
| `FileScanner` | scanners/file_scanner.dart | Unreachable `lib/` file detection. `reachableFiles()` and `resolveUri()` are public. |
| `CodeScanner` | scanners/code_scanner.dart | Unused declaration and method detection. |
| `DeclarationUtils` | scanners/declaration_utils.dart | `nameOf`, `kindOf`, `containerNameOf`, `membersOf`, `hasAnnotation`, `locate`. |
| `FileCleaner` | cleaners/file_cleaner.dart | `clean(item) → CleanResult`. Static `removeRange`. |
| `TrimItem` & enums | models/trim_item.dart | Finding model, `toJson()` used by `--json`. |
| `ExitCodes` | models/trim_item.dart | 0, 1, 64, 66, 70, 78. |
| `TrimException` | models/trim_item.dart | User-facing error with an exit code. |
| `TrimConfig` | utils/config_loader.dart | Immutable config with `fromMap` and `copyWith`. |
| `ConfigLoader` | utils/config_loader.dart | Loads `flutter_trim.yaml` (supports a nested `flutter_trim:` key). |
| `PathFilter` | utils/config_loader.dart | `isGenerated`, `isExcluded`, `canReport`. |

## Where to change things

| Task | Touch |
| --- | --- |
| Add or alter a CLI flag | `command_runner.dart` (parser, `_trim`, `_printUsage`), README table, PRD FR-6 |
| Add a config key | `TrimConfig` (field, ctor, `fromMap`, `copyWith`), README, PRD FR-7, test |
| Change what's "generated" | `PathFilter.generatedSuffixes` / `isGenerated`, README |
| Protect another framework method | `CodeScanner._conventionalMethods` |
| Change asset matching | `AssetScanner._isReferenced` / `_buildCorpus` |
| Change import resolution | `FileScanner.resolveUri`, `ProjectContext.fileAt` + the "Import resolution" tests |
| Change entry-point rules | `FileScanner._entryPoints` |
| Change declaration kinds | `DeclarationUtils` + `DeclarationKind` (both scanner and cleaner) |
| Change deletion formatting | `FileCleaner.removeRange` + its unit test |
| Terminal look | `Ui` (primitives), `TrimReporter`, `InteractivePrompt._describe` |
| JSON report shape | `TrimItem.toJson`, `TrimCommandRunner._printJson`, README "JSON output" |
| Version bump | `pubspec.yaml` + `lib/src/version.dart` + `CHANGELOG.md` |
