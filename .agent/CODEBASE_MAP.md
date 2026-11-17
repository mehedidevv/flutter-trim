# Codebase map

```
flutter_sweeper/
├── bin/
│   └── flutter_sweeper.dart        # main(): runs SweeperCommandRunner, flushes stdio, exit(code)
├── lib/
│   ├── flutter_sweeper.dart        # Public barrel export (the programmatic API surface)
│   └── src/
│       ├── version.dart            # packageVersion: keep in sync with pubspec.yaml
│       ├── cli/
│       │   ├── command_runner.dart     # SweeperCommandRunner: ArgParser, pipeline, git check, usage
│       │   └── interactive_prompt.dart # InteractivePrompt + PromptDecision enum
│       ├── scanners/
│       │   ├── project_context.dart    # ProjectContext, ParsedDartFile, keepMarker, ignoreFileMarker
│       │   ├── asset_scanner.dart      # AssetScanner (+ flutterGenName), _AssetDeclarations
│       │   ├── file_scanner.dart       # FileScanner: entry points + import-graph BFS
│       │   ├── code_scanner.dart       # CodeScanner, _Usage, _Candidate
│       │   └── declaration_utils.dart  # DeclarationUtils: shared by CodeScanner & FileCleaner
│       ├── cleaners/
│       │   └── file_cleaner.dart       # FileCleaner, CleanResult, removeRange
│       ├── models/
│       │   └── sweep_item.dart         # SweepItem, SweepItemType, DeclarationKind, ExitCodes, SweeperException
│       └── utils/
│           ├── config_loader.dart      # SweeperConfig, ConfigLoader, PathFilter (generated-file rules)
│           └── logger.dart             # SweepReporter, SweepStats, formatBytes, paint
├── test/
│   └── scanner_test.dart           # All tests + createFixture() temp-project builder
├── example/
│   ├── example.dart                # Runnable programmatic example (pub.dev "Example" tab)
│   └── README.md                   # CLI usage examples
├── .github/
│   ├── workflows/ci.yml            # Format, analyze, test (3 OSes), publish dry run, lowest deps
│   ├── workflows/publish.yml       # Tag vX.Y.Z → automated pub.dev publish (OIDC)
│   ├── ISSUE_TEMPLATE/             # Bug / false positive, feature request
│   └── pull_request_template.md
├── CONTRIBUTING.md                 # Dev setup, checks, release steps
├── README.md                       # User docs (pub.dev landing page)
├── CHANGELOG.md                    # Release notes
├── LICENSE                         # MIT
├── analysis_options.yaml           # lints/recommended + strict-casts/raw-types + extra rules
├── pubspec.yaml                    # Package metadata, deps, executables (fsweep, flutter_sweeper)
├── .gitignore
├── .pubignore                      # Overrides .gitignore for publishing; excludes .agent/, .github/, IDE/build files
└── .agent/                         # This knowledge base
```

## Symbol index

| Symbol | File | Responsibility |
| --- | --- | --- |
| `SweeperCommandRunner` | cli/command_runner.dart | CLI entry. `run(args) → Future<int>`. Injectable `Logger` and `interactive`. |
| `InteractivePrompt` | cli/interactive_prompt.dart | Per-item Keep/Delete loop, preview, stats. |
| `PromptDecision` | cli/interactive_prompt.dart | `keep, delete, deleteAll, quit` with labels. |
| `ProjectContext` | scanners/project_context.dart | Root, package name, pubspec, config, filter, parsed files. |
| `ParsedDartFile` | scanners/project_context.dart | Content, AST, line info, identifier tokens, ignore/partOf flags. |
| `AssetScanner` | scanners/asset_scanner.dart | Unused asset detection. |
| `FileScanner` | scanners/file_scanner.dart | Unreachable `lib/` file detection. `reachableFiles()` is public. |
| `CodeScanner` | scanners/code_scanner.dart | Unused declaration and method detection. |
| `DeclarationUtils` | scanners/declaration_utils.dart | `nameOf`, `kindOf`, `containerNameOf`, `membersOf`, `hasAnnotation`, `locate`. |
| `FileCleaner` | cleaners/file_cleaner.dart | `clean(item) → CleanResult`. Static `removeRange`. |
| `SweepItem` & enums | models/sweep_item.dart | Finding model. |
| `ExitCodes` | models/sweep_item.dart | 0, 1, 64, 66, 70, 78. |
| `SweeperException` | models/sweep_item.dart | User-facing error with an exit code. |
| `SweeperConfig` | utils/config_loader.dart | Immutable config with `fromMap` and `copyWith`. |
| `ConfigLoader` | utils/config_loader.dart | Loads `flutter_sweeper.yaml` (supports a nested `flutter_sweeper:` key). |
| `PathFilter` | utils/config_loader.dart | `isGenerated`, `isExcluded`, `canReport`. |
| `SweepReporter` | utils/logger.dart | Header, tables, summary. |
| `SweepStats` | utils/logger.dart | Mutable counters for a session. |
| `formatBytes`, `paint` | utils/logger.dart | Formatting helpers. |

## Where to change things

| Task | Touch |
| --- | --- |
| Add or alter a CLI flag | `command_runner.dart` (parser, `_sweep`, `_printUsage`), README table, PRD FR-6 |
| Add a config key | `SweeperConfig` (field, ctor, `fromMap`, `copyWith`), README, PRD FR-7, test |
| Change what's "generated" | `PathFilter.generatedSuffixes` / `isGenerated`, README |
| Protect another framework method | `CodeScanner._conventionalMethods` |
| Change asset matching | `AssetScanner._isReferenced` / `_buildCorpus` |
| Change entry-point rules | `FileScanner._entryPoints` |
| Change declaration kinds | `DeclarationUtils` + `DeclarationKind` (both scanner and cleaner) |
| Change deletion formatting | `FileCleaner.removeRange` + its unit test |
| Terminal look | `SweepReporter`, `InteractivePrompt._describe` |
| Version bump | `pubspec.yaml` + `lib/src/version.dart` + `CHANGELOG.md` |
