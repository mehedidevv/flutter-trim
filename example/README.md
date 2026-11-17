# flutter_trim examples

```sh
# Install once
dart pub global activate flutter_trim

# From the root of a Flutter app
ftrim --dry-run           # see what is unused
ftrim                     # review items one by one
ftrim --assets-only       # assets only
ftrim -e "lib/legacy/**"  # never report the legacy folder
ftrim --json > report.json
```

Optional `flutter_trim.yaml`:

```yaml
exclude:
  - lib/generated/**
keep:
  - LegacyApiClient
scan:
  methods: false
```

For programmatic use, see [example.dart](example.dart).
