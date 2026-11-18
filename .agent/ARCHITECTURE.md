# Architecture: flutter_trim

## 1. High-level view

```
bin/flutter_trim.dart
        │  run(args) → exit code
        ▼
┌──────────────────────────── CLI layer (lib/src/cli) ────────────────────────────┐
│ TrimCommandRunner                                                               │
│   parse args → load config → ProjectContext.load → scanners → report → prompt  │
│ TrimReporter / InteractivePrompt  → render with Ui (boxes, tables, progress)    │
└──────────────┬──────────────────────────────┬───────────────────────────────────┘
               │                              │
               ▼                              ▼
┌──── Scanners (lib/src/scanners) ────┐   ┌── Cleaner (lib/src/cleaners) ──┐
│ ProjectContext  (parse once, share) │   │ FileCleaner                     │
│ AssetScanner    → List<TrimItem>    │   │  delete files / remove AST node │
│ FileScanner     → List<TrimItem>    │   │  re-parse + syntax-error guard  │
│ CodeScanner     → List<TrimItem>    │   └────────────┬────────────────────┘
│ DeclarationUtils (shared w/ cleaner)│◄───────────────┘
└──────────────┬──────────────────────┘
               ▼
┌── Models & utils ────────────────────────────────────────────────┐
│ TrimItem, TrimItemType, DeclarationKind, ExitCodes,              │
│ TrimException (models/trim_item.dart)                            │
│ TrimConfig, ConfigLoader, PathFilter (utils/config_loader)       │
└──────────────────────────────────────────────────────────────────┘
```

Dependencies only point **downward**: CLI → scanners/cleaner → models/utils.
Scanners never print. All output goes through `mason_logger.Logger`, which is
owned by the CLI layer; layout primitives live in `cli/ui.dart`.

## 2. Run pipeline (`TrimCommandRunner._trim`)

1. **Validate input.** `--path` must exist and contain `pubspec.yaml`
   (otherwise exit 66). Flag conflicts give exit 64.
2. **Config.** `ConfigLoader.load(root)` reads `flutter_trim.yaml`, then
   CLI overrides are merged with `copyWith`: `--exclude` is *appended*, and
   `--[no-]methods` *replaces* `scan.methods` only if it was passed
   explicitly (`results.wasParsed`). `--json` implies dry run.
3. **Banner** (skipped for `--json`): project, mode, scope.
4. **Context.** `ProjectContext.load` parses the pubspec and every `.dart`
   file in `lib, bin, test, integration_test, test_driver, tool`. Hidden path
   segments are skipped. Files are decoded leniently (invalid UTF-8 is
   replaced); anything still unreadable goes into `skippedFiles` and
   produces a visible warning.
5. **Scan**, in this fixed order, each behind a spinner (`_step`):
   1. `AssetScanner` (unless `--code-only` / `scan.assets: false`)
   2. `FileScanner` (unless `--assets-only` / `scan.files: false`)
   3. `CodeScanner(skipFiles: unusedFiles)`. This needs the FileScanner
      output, so declarations in dead files aren't reported twice.
6. **Output.** `--json` → `_printJson` and exit. No items → `printClean`.
   Otherwise `printReport` (summary table + one table per category).
7. **Exit early** for dry runs or a non-interactive terminal.
   `--fail-on-findings` turns "items found" into exit 1 on these paths.
8. **Git safety check.** Walk up the folders looking for `.git` (a dir or a
   file, which supports worktrees and submodules). If none is found, ask to
   confirm.
9. **Interactive loop.** `InteractivePrompt.run` shows a card per item,
   calls `FileCleaner.clean` on Delete and returns `TrimStats`.
10. **Session summary** with next steps. Exit 1 if any deletion failed.

## 3. Core data model

`TrimItem` is the only currency between layers. It is immutable and holds:
`type` (asset | file | declaration), `path` (absolute), `relativePath`
(posix), `name`, `sizeBytes`, `reason`, plus the optional `lineNumber`,
`kind`, `parentName` and `companionPaths`. Derived values: `typeLabel`,
`displayName` (`Parent.method`), `location` (`path:line`), and
`isDeclaration`. `toJson()` feeds `--json`.

## 4. Key components and algorithms

### 4.1 ProjectContext: "parse once"
- `ParsedDartFile` holds `content`, `CompilationUnit` (from `parseString`,
  `throwIfDiagnostics: false`) and `LineInfo`, plus these lazy values:
  - `identifiers`: every identifier token from the token stream. Comments
    aren't tokens, so `/// [Foo]` doesn't count as a usage.
  - `isIgnored`: the content contains `flutter_trim:ignore_file`.
  - `isPartOf`: the file has a `part of` directive.
- Paths: the absolute form is OS-native and normalized. The relative form
  always uses `/`.
- `fileAt(path)`: exact match first, then a **case-insensitive** match.
  macOS and Windows compile imports whose case differs from the file on disk
  (`gatewayController.dart` → `gateWayController.dart`), so such files are
  used. On case-sensitive systems these imports would not compile, so the
  fallback never hides a real problem.
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
- `resolveUri(uri, fromFile)` uses `Uri.parse`, so `pathSegments` are
  **percent-decoded** (`common%20widget` → `common widget`).
  `package:<self>/x` maps to `lib/x`. Other packages, `dart:` and anything
  with a scheme or authority are ignored. Relative URIs resolve against the
  importing file's folder.
- Every resolved target goes through `ProjectContext.fileAt`, and the BFS
  stores the *on-disk* path, so case-mismatched imports keep the walk going.
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
  away with the parent. The same applies to fields.
- Variables (since 1.2): `TopLevelVariableDeclaration` and
  `FieldDeclaration` with exactly **one** variable
  (`DeclarationUtils.singleVariableName`), so removal always takes out a
  whole statement. Fields skip `@override`, `abstract`, `external`
  (`_hasModifier` walks tokens; no version-specific keyword getters).
  Gated by `includeVariables` / `scan.variables` / `--[no-]variables`.
- Links (since 1.2): `cli/links.dart` `Linker` renders cwd-relative
  `path:line`. In VS Code/Cursor (`TERM_PROGRAM=vscode`) and JetBrains
  (`TERMINAL_EMULATOR=JetBrains-JediTerm`) terminals it leaves plain text
  (they link it with the line); otherwise it wraps an OSC 8 hyperlink.
  `visibleLength` strips OSC 8 markers.
- Protection layers, in order: `main`, the `keep` list, `@pragma` or
  `@protected` metadata, a `// flutter_trim:keep` marker in the region
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
- `dryRun` mode computes the results without writing (API only).

### 4.6.1 BackupStore: undo
- The CLI creates `BackupStore.start(root)` per interactive session (unless
  `--no-backup`) and passes it to `FileCleaner(backup:)`.
- Right before writing/deleting, `FileCleaner` calls `save(label, paths)`,
  which copies the originals to
  `<root>/.flutter_trim/backups/<session>/<id>/<relative path>` and appends an
  entry to `manifest.json`. If the copy fails, nothing is deleted.
- `InteractivePrompt` keeps a stack of `(item, backupId)` and offers
  **Undo last delete**; `restore(id)` copies the files back and marks the
  entry `restored`.
- `ftrim --restore` → `BackupStore.latest(root).restoreAll()` (newest first,
  so several edits of one file unwind correctly).
- The folder starts with a dot, so `ProjectContext` and `AssetScanner` never
  scan it.

### 4.7 Config and filtering
- `TrimConfig` is immutable and has `fromMap` and `copyWith`. Unknown
  keys are ignored.
- `PathFilter.canReport = !isGenerated && !isExcluded`. Globs use
  `p.posix` context and are matched against project-relative paths.
- Generated files are *filtered out of findings* but stay *in the corpus and
  usage index*.

### 4.8 Presentation
- `Ui` (cli/ui.dart) renders rounded boxes (title + trailing text on the top
  border, sections split by rules), bordered tables (right-aligned columns,
  one `shrink` column that is shortened from the start so file names stay
  visible) and a progress bar. Width = terminal columns − 4, clamped to
  60–110. All width math uses `visibleLength`, which ignores ANSI codes.
- `TrimReporter`: banner box, settings, summary table with a total row,
  per-category tables (files and assets show the *folder*; declarations
  show `path:line`), clean / dry-run messages, session summary box with
  next steps.
- `InteractivePrompt`: one box per item (color by type, `n / total`,
  6-line code preview for declarations), progress bar with running counts,
  then `logger.chooseOne` (arrow keys) and `logger.confirm` for bulk delete.

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
| D11 | Version-agnostic AST access (tokens and `childEntities`) | One release supports analyzer 6–14, so it works on Dart 3.0 through the latest SDK | Slightly less direct code. New analyzer majors must be checked. |
| D12 | Percent-decode URIs and match files case-insensitively as a fallback | Real apps use folders with spaces and inconsistent file-name casing; exact matching reported used files (found on 400–600 file apps) | A case-insensitive match could, in theory, pick the wrong file when two files differ only by case; that layout cannot exist on macOS/Windows and is very rare elsewhere. |
| D13 | Read sources with `allowMalformed: true` | A file that fails to decode would drop its references and cause false positives | Replacement characters in comments/strings only. |

## 6. Extension points

- **New scanner:** implement `List<TrimItem> scan()` using `ProjectContext`.
  Add a `TrimItemType` if needed (and update `TrimReporter.title`, the
  colors in `InteractivePrompt._colorFor` and the `FileCleaner.clean`
  switch). Wire it into `_trim` with `_step(...)`, add a `scan.<key>` config
  flag, export it from the barrel, and add tests.
- **New declaration kind:** extend `DeclarationKind` and
  `DeclarationUtils.kindOf` / `locate`. Check that `removeRange` handles it.
- **New output format:** follow `--json` (`_printJson`), and keep human
  output going through `Logger`.
