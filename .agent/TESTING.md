# Testing guide

## Running

```sh
dart pub get
dart test                              # all tests
dart test --name "CodeScanner"         # one group
dart test --plain-name "removes a single method"
dart analyze                           # static checks (part of "green")
```

No Flutter SDK is needed. The fixture is only parsed, never resolved.

> **Current status (2026-11-17):** 24/24 tests pass on analyzer 14.5.0.
> CI also analyzes `lib/` against the lowest dependency versions
> (`dart pub downgrade`).

## Structure

Everything lives in `test/scanner_test.dart`:

| Group | Covers |
| --- | --- |
| `AssetScanner` | Declared vs undeclared unused assets, exclude globs, `flutterGenName` |
| `FileScanner` | Unreachable library with its `part` companion, configured entry points |
| `CodeScanner` | Unused class, function and methods; protections (`keep` marker, `@pragma`, `@override`, `main`, private-but-used); `--no-methods`; line numbers |
| `FileCleaner` | Class removal with doc comment (re-parses clean), method removal, file and part deletion, dry run, missing file, `removeRange` blank-line handling |
| `ConfigLoader` | YAML parsing and its effect on scanners |
| `SweeperCommandRunner` | `--version`, conflicting flags (64), dry run doesn't delete, missing pubspec (66) |
| `DeclarationUtils` | Names after class modifiers (`abstract base`, `sealed`), enums, mixins, typedefs; abstract methods never reported |
| (top level) | `packageVersion` equals the pubspec `version` |

### The fixture: `createFixture({String? sweeperConfig})`
Creates a temp folder `flutter_sweeper_test_*` containing a fake Flutter
app named `demo_app`. `setUp` builds it and `tearDown` deletes it.

Expected findings (keep these stable, since many tests rely on them):
- **Unused assets:** `assets/images/old_banner.png` (declared) and
  `assets/raw/orphan.txt` (undeclared).
- **Used assets:**
  - `logo.png` and its `2.0x` variant (literal path)
  - `avatar.png` (via `'$imagesDir/avatar.png'`)
  - `config.json` (literal string)
  - `app_icon.png` (`flutter_launcher_icons` pubspec key)
  - the Roboto font (a font declaration)
  - `.DS_Store` (ignored)
- **Unreachable file:** `lib/legacy/old_screen.dart`, with companion
  `old_screen.g.dart`.
- **Unused declarations:** `UnusedWidget`, `unusedHelper`,
  `UsedService.neverCalled` (self-recursive), and `StringX.shout`.
- **Must NOT report:**
  - `Home`, `UsedService`, `fetch` and `_load` (used)
  - `keptHelper` (keep marker)
  - `backgroundCallback` (`@pragma`)
  - `main`
  - `OldScreen` (inside an already-reported dead file)
  - `UnusedWidget.create` (its parent is unused)
- `UnusedWidget` is on **line 18** of `lib/widgets/home.dart`. Adding lines
  above it in the fixture breaks `records line numbers`.

## Writing tests

- Build on `createFixture()`. Add files with the local `write()` helper
  pattern, or create a new fixture variant when the change is large.
- For every new detection rule, add **one positive** ("reports X") and **at
  least one negative** ("does not report Y") test.
- For cleaner changes, assert that the resulting file has
  `parseString(...).errors` empty, and check exact output for `removeRange`.
- Runner tests: inject `Logger(level: Level.quiet)`, pass `interactive:
  false`, and assert exit codes via `ExitCodes`.
- Use `addTearDown` to clean up any extra temp folders.
- If a matcher needs more than 7 alternatives, use separate `expect`s or
  `isNot(contains(x))` per item. Don't use `anyOf` with more than 7 arguments.

## Gaps worth covering

- `InteractivePrompt` decision flow (use a fake `Logger` that returns
  scripted choices for `chooseOne` and `confirm`).
- `SweepReporter` table rendering and `_fit` truncation.
- Conditional imports, `export`-only reachability, and packages with no `main`.
- flutter_gen projects (getter-based asset usage).
- Map-style asset entries (`- path:`) and the `packages/` skip.
- `ignore_file` marker; nested `flutter_sweeper:` config key; invalid YAML
  (exit 78).
- The non-git warning path.
- Windows path handling (the CI matrix should include windows-latest).

## Manual verification checklist (before release)

```sh
dart run bin/flutter_sweeper.dart --help
dart run bin/flutter_sweeper.dart --version
dart run bin/flutter_sweeper.dart -p <real_flutter_app> --dry-run
dart run bin/flutter_sweeper.dart -p <real_flutter_app> --dry-run --code-only --no-methods
dart run bin/flutter_sweeper.dart -p <real_flutter_app> | cat   # non-TTY → report only
# On a throwaway git copy:
dart run bin/flutter_sweeper.dart -p <copy>   # Delete a few items, then:
(cd <copy> && dart fix --apply && flutter analyze && flutter test)
```
