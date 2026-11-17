# Architecture: flutter_sweeper

## 1. High-level view

```
bin/flutter_sweeper.dart
        │  run(args) → exit code
        ▼
┌──────────────────────────── CLI layer (lib/src/cli) ────────────────────────────┐
│ SweeperCommandRunner                                                            │
│   parse args → load config → ProjectContext.load → scanners → report → prompt  │
│ InteractivePrompt  (Keep / Delete / Delete all / Quit loop)                     │
└──────────────┬──────────────────────────────┬───────────────────────────────────┘
               │                              │
               ▼                              ▼
┌──── Scanners (lib/src/scanners) ────┐   ┌── Cleaner (lib/src/cleaners) ──┐
│ ProjectContext  (parse once, share) │   │ FileCleaner                     │
│ AssetScanner    → List<SweepItem>   │   │  delete files / remove AST node │
│ FileScanner     → List<SweepItem>   │   │  re-parse + syntax-error guard  │
│ CodeScanner     → List<SweepItem>   │   └────────────┬────────────────────┘
│ DeclarationUtils (shared w/ cleaner)│◄───────────────┘
└──────────────┬──────────────────────┘
               ▼
┌── Models & utils ────────────────────────────────────────────────┐
│ SweepItem, SweepItemType, DeclarationKind, ExitCodes,            │
│ SweeperException (models/sweep_item.dart)                        │
│ SweeperConfig, ConfigLoader, PathFilter (utils/config_loader)    │
│ SweepReporter, SweepStats, formatBytes, paint (utils/logger)     │
└──────────────────────────────────────────────────────────────────┘
```

Dependencies only point **downward**: CLI → scanners/cleaner → models/utils.
Scanners never print. All output goes through `mason_logger.Logger`, which is
owned by the CLI layer.

## 2. Run pipeline (`SweeperCommandRunner._sweep`)

1. **Validate input.** `--path` must exist and contain `pubspec.yaml`
   (otherwise exit 66). Flag conflicts give exit 64.
2. **Config.** `ConfigLoader.load(root)` reads `flutter_sweeper.yaml`, then
   CLI overrides are merged with `copyWith`: `--exclude` is *appended*, and
   `--[no-]methods` *replaces* `scan.methods` only if it was passed
   explicitly (`results.wasParsed`).
3. **Context.** `ProjectContext.load` parses the pubspec and every `.dart`
   file in `lib, bin, test, integration_test, test_driver, tool`. Hidden path
   segments are skipped. Parse failures go into `skippedFiles`.
4. **Scan**, in this fixed order:
   1. `AssetScanner` (unless `--code-only` / `scan.assets: false`)
   2. `FileScanner` (unless `--assets-only` / `scan.files: false`)
   3. `CodeScanner(skipFiles: unusedFiles)`. This needs the FileScanner
      output, so declarations in dead files aren't reported twice.
5. **Report.** `SweepReporter.printReport` shows grouped box-drawing tables.
6. **Exit early** if there are no items, it's a dry run, or the terminal
   isn't interactive.
7. **Git safety check.** Walk up the folders looking for `.git` (a dir or a
   file, which supports worktrees and submodules). If none is found, ask to
   confirm.
8. **Interactive loop.** `InteractivePrompt.run` calls `FileCleaner.clean`
   per item and returns `SweepStats`.
9. **Summary.** Exit 1 if any deletion failed, otherwise 0.

## 3. Core data model

`SweepItem` is the only currency between layers. It is immutable and holds:
`type` (asset | file | declaration), `path` (absolute), `relativePath`
(posix), `name`, `sizeBytes`, `reason`, plus the optional `lineNumber`,
`kind`, `parentName` and `companionPaths`. Derived values: `typeLabel`,
`displayName` (`Parent.method`), `location` (`path:line`), and
`isDeclaration`. `toJson()` exists for future machine output.

## 4. Key components and algorithms

### 4.1 ProjectContext: "parse once"
- `ParsedDartFile` holds `content`, `CompilationUnit` (from `parseString`,
  `throwIfDiagnostics: false`) and `LineInfo`, plus these lazy values:
  - `identifiers`: every identifier token from the token stream. Comments
    aren't tokens, so `/// [Foo]` doesn't count as a usage.
  - `isIgnored`: the content contains `flutter_sweeper:ignore_file`.
  - `isPartOf`: the file has a `part of` directive.
- Paths: the absolute form is OS-native and normalized. The relative form
  always uses `/`. `fileAt()` looks a file up by its normalized absolute path.
- `usesFlutterGen`: a `flutter_gen`/`flutter_gen_runner` dependency, or an
  `assets.gen.dart` file.

### 4.2 AssetScanner: text-corpus matching
- **Candidates:** declared files, plus a recursive walk of
  `asset_directories` and declared directories, minus declared font files.
- **Corpus:** all Dart contents (except `*.gen.dart`), plus every pubspec
  scalar except `flutter.assets`/`flutter.fonts`, plus root-level YAML
  configs.
- **Match order:**
  1. Full or base path is a substring of the corpus.
  2. The file name matches with a left boundary `(^|[^A-Za-z0-9_\-])`.
  3. flutter_gen: `flutterGenName(file)` (camelCase of the stem) is found in
     the identifiers of hand-written files.
- Complexity: about O(candidates × corpus size). A regex is compiled per
  candidate.

### 4.3 FileScanner: reachability BFS
- Entry points, then a BFS over `NamespaceDirective` URIs (including the
  `configurations` used by conditional imports) and `PartDirective` URIs.
- `_resolve`: `package:<self>/x` maps to `lib/x`. Other packages, `dart:`
  and anything with a scheme are ignored. Relative URIs resolve against the
  importing file's folder.
- Findings are unreachable `lib/` files that aren't `part of`, ignored or
  filtered. Their `part` URIs become companions.

### 4.4 CodeScanner: name-based usage index
- `_indexUsages`: `Map<lexeme, List<_Usage(path, offset)>>` built from
  **every** project file, including tests and generated code.
- `_collect`: walks the top-level members of reportable `lib/` files.
  `DeclarationUtils.kindOf` decides whether a member is reportable;
  containers (class, mixin, enum, extension) also produce method candidates.
- `isUsed(candidate)`: some usage of the name exists outside
  `[node.offset, node.end)` in the declaring file. This makes self
  references (constructors, recursion, static factories) not count.
- Methods whose parent container is unused are dropped, because they go
  away with the parent.
- Protection layers, in order: `main`, the `keep` list, `@pragma` or
  `@protected` metadata, a `// flutter_sweeper:keep` marker in the region
  from the line above the node through its first non-comment token. Methods
  are also skipped for operators, getters, setters, abstract, external,
  `@override`, `_conventionalMethods`, and a container with `@pragma`.

### 4.5 DeclarationUtils: the shared contract
Both `CodeScanner` (discovery) and `FileCleaner` (removal) use
`kindOf / nameOf / containerNameOf / membersOf / locate`. **Any change to what
counts as a declaration must be made here**, so the two sides never disagree.
Unnamed extensions get the label `<unnamed extension>`.

**Analyzer compatibility (6.x–14.x):** analyzer 11 removed
`NamedCompilationUnitMember`, `ClassDeclaration.name/members` and
`EnumDeclaration.name/members`. `DeclarationUtils` therefore:
- reads class and enum names as the first identifier token after
  `classKeyword` / `enumKeyword` (which skips `const` of primary
  constructors),
- finds members by walking `childEntities` down to the first `ClassMember`
  nodes (this works whether members sit directly on the declaration or inside
  a `BlockClassBody`).

`CodeScanner` detects abstract methods with `body is EmptyFunctionBody`,
because `isAbstract` is deprecated.

### 4.6 FileCleaner: safe mutation
- Assets and files: delete the main path and its companions. Missing files
  are skipped. If nothing was removed, it fails.
- Declarations: **re-read and re-parse at deletion time**. Offsets are never
  cached from the scan, so several deletions in one file stay correct. Then:
  `locate` → `removeRange(content, node.offset, node.end)` (the node range
  already includes the doc comment and annotations) → re-parse → reject if
  `errorsAfter > errorsBefore` → write.
- `removeRange` also removes the leading indentation (only if the text to
  its left is whitespace back to a newline), the trailing whitespace, CR/LF,
  and one extra blank line when the line before is blank, `{`, or the start
  of the file.
- `dryRun` mode computes the results without writing. The CLI doesn't use
  it today, because `--dry-run` exits before cleaning.

### 4.7 Config and filtering
- `SweeperConfig` is immutable and has `fromMap` and `copyWith`. Unknown
  keys are ignored.
- `PathFilter.canReport = !isGenerated && !isExcluded`. Globs use
  `p.posix` context and are matched against project-relative paths.
- Generated files are *filtered out of findings* but stay *in the corpus and
  usage index*.

### 4.8 Presentation
- `SweepReporter`: header, grouped tables (columns are capped at
  `[4,12,40,60,10]`, values are left-truncated with `…` so file names stay
  visible), and the summary.
- `InteractivePrompt`: `logger.chooseOne` with arrow-key navigation,
  `logger.confirm`, and the code preview (4 lines from the declaration
  line).

## 5. Design decisions (ADR-style summary)

| # | Decision | Rationale | Trade-off |
| --- | --- | --- | --- |
| D1 | Unresolved `parseString` instead of `AnalysisContextCollection` | No Flutter SDK or `pub get` needed in the target project; fast | No type information. Matching is by name only. |
| D2 | Name-based usage, global across files | Simple, conservative, never reports used code | Name collisions hide dead code (accepted). |
| D3 | Tests and generated code count as references | Safety | Code used only by tests survives. |
| D4 | Asset matching by substring and file name over a text corpus | Catches strings, interpolation, configs and YAML tools | Constant files make everything look used. |
| D5 | Re-parse before every declaration removal | Correct offsets after earlier edits | Extra parse per deletion (cheap). |
| D6 | Syntax-error guard (error count comparison) | Never corrupt user files | Doesn't catch *semantic* breakage, so we suggest analyze/fix. |
| D7 | Shared `DeclarationUtils` | Scanner and cleaner agree | Must be kept as the single source of truth. |
| D8 | Non-TTY → report only | CI-safe and pipe-safe | No `--yes` auto-delete mode yet. |
| D9 | sysexits exit codes | Standard and scriptable | |
| D10 | `Logger` and `interactive` are injectable in the runner | Testable without a TTY | |
| D11 | Version-agnostic AST access (tokens and `childEntities`) | One release supports analyzer 6–14, so it works on Dart 3.0 through the latest SDK and gets full pub points for up-to-date dependencies | Slightly less direct code. New analyzer majors must be checked. |

## 6. Extension points

- **New scanner:** implement `List<SweepItem> scan()` using `ProjectContext`.
  Add a `SweepItemType` if needed (and update `_title` in the reporter and
  the `FileCleaner.clean` switch). Wire it into `_sweep` with `_scan(label, …)`,
  add a `scan.<key>` config flag, export it from the barrel, and add tests.
- **New declaration kind:** extend `DeclarationKind` and
  `DeclarationUtils.kindOf` / `locate`. Check that `removeRange` handles it.
- **New output format** (for example `--json`): use `SweepItem.toJson()` in
  the runner, and keep human output going through `Logger`.
