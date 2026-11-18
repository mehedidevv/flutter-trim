/// Find and interactively remove unused assets, Dart files, classes,
/// functions and methods from Flutter projects.
///
/// Most people use the `ftrim` / `flutter_trim` executables. The scanners
/// are exported as well so they can be embedded in other tooling:
///
/// ```dart
/// final context = ProjectContext.load('path/to/app');
/// final unusedAssets = AssetScanner(context).scan();
/// ```
library;

export 'src/cleaners/backup_store.dart'
    show BackupEntry, BackupStore, backupDirName;
export 'src/cleaners/file_cleaner.dart' show CleanResult, FileCleaner;
export 'src/cli/command_runner.dart' show TrimCommandRunner;
export 'src/cli/interactive_prompt.dart' show InteractivePrompt, PromptDecision;
export 'src/cli/reporter.dart' show TrimReporter, TrimStats;
export 'src/cli/ui.dart' show formatBytes;
export 'src/models/trim_item.dart';
export 'src/scanners/asset_scanner.dart' show AssetScanner;
export 'src/scanners/code_scanner.dart' show CodeScanner;
export 'src/scanners/file_scanner.dart' show FileScanner;
export 'src/scanners/project_context.dart'
    show ParsedDartFile, ProjectContext, ignoreFileMarker, keepMarker;
export 'src/utils/config_loader.dart' show ConfigLoader, PathFilter, TrimConfig;
export 'src/version.dart';
