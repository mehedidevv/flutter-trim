# Changelog

## 1.0.0

- Initial release.
- `fsweep` / `flutter_sweeper` executables.
- Unused asset detection: pubspec declarations, undeclared files in asset
  folders, resolution variants, tool configs and flutter_gen getters.
- Unreferenced Dart file detection through an import/export/part graph,
  including conditional imports; part files are deleted with their library.
- AST-based detection of unused classes, mixins, enums, typedefs, top-level
  functions and methods.
- Interactive Keep / Delete / Delete all remaining / Skip all workflow with
  code previews.
- Safe declaration removal that keeps doc comments and annotations together
  and refuses edits that would add syntax errors.
- `--dry-run`, `--assets-only`, `--code-only`, `--exclude`, `--[no-]methods`
  and `--path` flags.
- Optional `flutter_sweeper.yaml` config plus `// flutter_sweeper:keep` and
  `// flutter_sweeper:ignore_file` markers.
- Works with `package:analyzer` 6.x through 14.x, so it installs on Dart 3.0
  and on the latest SDKs.
- Programmatic API with a runnable example in `example/example.dart`.
