# Contributing to flutter_trim

Thanks for helping! Bug reports, false-positive reports and pull requests are
all welcome.

## Reporting a false positive

flutter_trim must never report code or assets that are actually used. If
it does, please open an issue with:

- the `ftrim` version (`ftrim --version`) and `dart --version`,
- the reported item (type, name, location),
- a minimal snippet showing how the item is used.

## Development setup

```sh
git clone https://github.com/mehedidevv/flutter-trim.git
cd flutter-trim
dart pub get
dart test
dart run bin/flutter_trim.dart --help
```

Try it on a real project without deleting anything:

```sh
dart run bin/flutter_trim.dart -p ../some_flutter_app --dry-run
```

## Before opening a pull request

```sh
dart format .
dart analyze --fatal-infos
dart test
```

- Add tests for new behaviour. For detection changes, add both a "reports X"
  and a "does not report Y" test (see `createFixture()` in
  `test/scanner_test.dart`).
- Prefer false negatives over false positives: when in doubt, treat
  something as used.
- Keep `DeclarationUtils` the single place that defines what a declaration
  is. Only use analyzer AST APIs available in every supported analyzer
  version (see the constraint in `pubspec.yaml`).
- Update `README.md` and add a `CHANGELOG.md` entry for user-visible changes.

## Releasing (maintainers)

1. Bump `version` in `pubspec.yaml` **and** `packageVersion` in
   `lib/src/version.dart` (a test checks they match).
2. Add the release notes to `CHANGELOG.md`.
3. Commit, then tag `vX.Y.Z` and push the tag. The `Publish to pub.dev`
   workflow uploads the package.

## License

By contributing you agree that your contributions are licensed under the MIT
License of this project.
