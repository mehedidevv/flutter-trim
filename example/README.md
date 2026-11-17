# flutter_sweeper examples

```sh
# Install once
dart pub global activate flutter_sweeper

# From the root of a Flutter app
fsweep --dry-run          # see what is unused
fsweep                    # review items one by one
fsweep --assets-only      # assets only
fsweep -e "lib/legacy/**" # never report the legacy folder
```

Optional `flutter_sweeper.yaml`:

```yaml
exclude:
  - lib/generated/**
keep:
  - LegacyApiClient
scan:
  methods: false
```
