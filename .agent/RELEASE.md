# Release and publishing

## Versioning
Semantic versioning:
- **Patch:** bug fixes, *fewer* false positives.
- **Minor:** new flags, config keys or scanners, new exports.
- **Major:** breaking changes to the exported API, CLI flags, config keys or
  exit codes.

The version lives in `pubspec.yaml` and `lib/src/version.dart`. A test
fails if they differ.

## State of flutter_trim 1.0.0 (2026-11-17)
Done:
- `dart format`, `dart analyze --fatal-infos` and `dart test` (32 tests)
  are all clean.
- Real-project accuracy check passed (see TESTING.md).
- `lib/` analyzes clean against the lowest dependency versions
  (`dart pub downgrade`).
- Dependencies allow the latest majors (analyzer <15, lints 6, test 1.x).
- The description is between 60 and 180 characters. Homepage, repository,
  issue_tracker and topics are set.
- `example/example.dart` and `example/README.md` exist.
- All public API members have dartdoc comments.
- `.pubignore` excludes `.agent/`, `.github/`, IDE and build files.
- `dart pub publish --dry-run`: **0 warnings**.
- CI (`.github/workflows/ci.yml`) and tag-based automated publishing
  (`publish.yml`).
- CONTRIBUTING.md, issue templates and a PR template.

- Repository URLs point at https://github.com/mehedidevv/flutter-trim,
  and the project is its own git repository.

Remaining (manual, by the owner):
- [ ] Enable automated publishing on pub.dev (see below).
- [ ] (Optional, for a "verified publisher" badge) verify a domain in Google
      Search Console and create a publisher on pub.dev.

## First publish

```sh
cd flutter-trim               # must be its own git repo (see KNOWN_ISSUES)
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test
dart pub publish --dry-run
dart pub publish              # opens a browser to log in with Google
git tag v1.0.0 && git push --tags
```

Then on pub.dev → package → **Admin**:
- Enable **Automated publishing** from GitHub Actions
  (repository `mehedidevv/flutter-trim`, tag pattern
  `v{{version}}`).
- Optionally transfer the package to your verified publisher.

## Later releases
1. Bump the version in both files and add a CHANGELOG section.
2. Commit, then `git tag vX.Y.Z && git push --tags`. The `Publish to pub.dev`
   workflow uploads the package.

## pub.dev scoring (160 points): how each category is covered
| Category | Covered by |
| --- | --- |
| Follow Dart file conventions (30) | Valid pubspec with URLs, README, CHANGELOG, OSI license (MIT) |
| Provide documentation (20) | `example/example.dart`, dartdoc on the public API |
| Platform support (20) | Pure Dart with `dart:io`, so all native platforms (no web, as expected for a CLI) |
| Pass static analysis (50) | Zero analyzer issues, formatted |
| Support up-to-date dependencies (40) | Constraints accept the latest versions, and the lowest versions analyze clean |
