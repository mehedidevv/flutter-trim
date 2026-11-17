# Development guidelines

These rules apply to human contributors and AI agents alike. When in doubt,
match the existing code.

## 1. Golden rules

1. **Safety first.** This tool deletes user files. Any change that could
   cause a *false positive* (reporting used code or assets) needs a test
   proving it doesn't happen. Prefer false negatives.
2. **Scanners are pure.** Scanners read `ProjectContext` and return
   `List<TrimItem>`. They don't print, prompt or write to disk. Only
   `FileCleaner` mutates files, and only the CLI layer talks to the user.
3. **One source of truth for declarations.** Anything about "what is a
   declaration / how to find it" lives in `DeclarationUtils`.
4. **Parse once.** Use `ProjectContext.dartFiles` and `ParsedDartFile`.
   Don't call `parseString` in scanners. The only extra parses allowed are in
   `FileCleaner`, for the before/after safety check.
5. **Paths:** store absolute paths in OS-native form, and compare, report and
   glob-match project-relative paths with `/` separators. Use
   `context.relative()` / `context.absolute()`. Never hand-concatenate with
   `'/'` for disk access.
6. **No new runtime dependencies** without a strong reason. Keep the install
   light.
7. **Keep docs in sync:** README, CHANGELOG, `.agent/*`, and
   `lib/src/version.dart` together with `pubspec.yaml`.

## 2. Dart style

Enforced by `analysis_options.yaml`:
- `package:lints/recommended.yaml`
- `strict-casts: true`, `strict-raw-types: true`, so always cast YAML/dynamic
  values explicitly (`results['x'] as bool`, `value is Map`).
- Lint rules: `always_declare_return_types`, `prefer_final_locals`,
  `prefer_single_quotes`, `require_trailing_commas`, `unawaited_futures`.

Conventions seen in the codebase:
- Dart 3 features are welcome: `switch` expressions, `if-case`
  (`if (_resolve(uri, path) case final part?)`), `abstract final class` for
  static-only holders, and enhanced enums with labels.
- Immutable value types with `const` constructors (`TrimItem`,
  `TrimConfig`, `CleanResult`). Use `copyWith` for overrides.
- Private helpers start with `_`. Private data classes (`_Usage`,
  `_Candidate`) stay file-local.
- Cascades (`..`) for repeated logger calls.
- Every public class and member gets a `///` doc comment explaining *why*,
  not just *what*.
- Errors that the user should see: throw `TrimException(message,
  exitCode:)`. Never `exit()` outside `bin/`.
- File-system errors during cleaning become `CleanResult.failure`, not
  exceptions.
- Use `on Object catch` only at top-level boundaries (the runner and
  per-file parsing).

Before committing:
```sh
dart format .
dart analyze --fatal-infos   # must report no issues at all
dart test
```

## 3. Terminal UX rules

- All output goes through `mason_logger.Logger` (`info`, `detail`, `warn`,
  `err`, `success`, `progress`). Never `print`.
- Wrap colors with `paint(code, text)` so they fall back when ANSI is off.
- Diagnostic or noisy output goes to `logger.detail` (shown with `-v`).
- Destructive bulk actions must ask `logger.confirm(..., defaultValue: false)`.
- Never prompt when the terminal isn't interactive.

## 4. Adding features: checklist

- [ ] Logic in the right layer (scanner / cleaner / CLI).
- [ ] Config flag in `TrimConfig` if the feature can be turned on or off.
- [ ] CLI flag, if any, in the parser **and** in `_printUsage` examples when
      useful.
- [ ] Exported from `lib/flutter_trim.dart` if it's public API (use `show`).
- [ ] Tests in `test/` using `createFixture()`, covering positives **and**
      "must not report" cases.
- [ ] README (Features / Usage / Configuration / Limitations), CHANGELOG
      entry under a new version or "Unreleased", and `.agent` docs updated.

## 5. Rules for AI agents

- Read `.agent/README.md` → the relevant doc → the actual source before
  editing. The docs can lag, and the code wins.
- Edit files with the IDE edit tools, not shell redirection or `sed`.
- Don't run `ftrim` *without* `--dry-run` against real projects, including
  this repo, unless the user asks. It deletes files.
- Don't change public API signatures (anything exported from the barrel)
  without flagging it as a breaking change and bumping the major version.
- Don't widen what gets reported (fewer protections, more candidates)
  without tests and an explicit note to the user.
- The `analyzer` constraint is `>=6.2.0 <15.0.0`. Only use AST APIs that
  exist in **all** of those versions. `NamedCompilationUnitMember`,
  `ClassDeclaration.name/members`, `EnumDeclaration.name/members` and
  `MethodDeclaration.isAbstract` are off-limits (see ARCHITECTURE §4.5).
  Verify with `dart pub downgrade && dart analyze lib`, then
  `dart pub upgrade && dart test`.
- Run `dart analyze` and `dart test` after changes and report the real
  results.
- Note: the git repository root for this folder is currently the user's home
  directory, not the project. Don't run broad git commands (`git add -A`,
  `git clean`, `git stash`) from here.

## 6. Commit / PR conventions

- Small, focused commits. Use imperative subjects (`Add --json output`,
  `Fix part-file companion size`).
- A PR description says what changed, why, how it was tested, and any change
  to reporting behaviour (more or fewer findings).
