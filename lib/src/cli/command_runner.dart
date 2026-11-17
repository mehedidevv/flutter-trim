import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

import '../cleaners/file_cleaner.dart';
import '../models/trim_item.dart';
import '../scanners/asset_scanner.dart';
import '../scanners/code_scanner.dart';
import '../scanners/file_scanner.dart';
import '../scanners/project_context.dart';
import '../utils/config_loader.dart';
import '../version.dart';
import 'interactive_prompt.dart';
import 'reporter.dart';
import 'ui.dart';

/// Parses CLI arguments and orchestrates scanning, reporting and cleaning.
class TrimCommandRunner {
  /// Creates a runner.
  ///
  /// Pass a [logger] to capture or silence output, and [interactive] to force
  /// (or disable) the interactive review instead of detecting a terminal.
  TrimCommandRunner({Logger? logger, bool? interactive})
      : _logger = logger ?? Logger(),
        _interactiveOverride = interactive;

  final Logger _logger;
  final bool? _interactiveOverride;

  /// The command-line options understood by `ftrim`.
  late final ArgParser parser = ArgParser(usageLineLength: 100)
    ..addOption(
      'path',
      abbr: 'p',
      defaultsTo: '.',
      valueHelp: 'dir',
      help: 'Root of the Flutter project to scan '
          '(the folder with pubspec.yaml).',
    )
    ..addFlag(
      'assets-only',
      negatable: false,
      help: 'Only look for unused assets.',
    )
    ..addFlag(
      'code-only',
      negatable: false,
      help: 'Only look for unused Dart files, classes, functions and methods.',
    )
    ..addFlag(
      'dry-run',
      abbr: 'n',
      negatable: false,
      help: 'Print the report and exit without deleting anything.',
    )
    ..addMultiOption(
      'exclude',
      abbr: 'e',
      valueHelp: 'glob',
      help: 'Never report paths matching this glob, relative to the project '
          'root (repeatable), e.g. "lib/legacy/**".',
    )
    ..addFlag(
      'methods',
      defaultsTo: true,
      help: 'Also report unused methods inside used classes.',
    )
    ..addFlag(
      'json',
      negatable: false,
      help: 'Print the findings as JSON (implies --dry-run).',
    )
    ..addFlag(
      'fail-on-findings',
      negatable: false,
      help: 'Exit with code 1 when anything unused is found (for CI).',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      negatable: false,
      help: 'Show diagnostic output.',
    )
    ..addFlag('version', negatable: false, help: 'Print the version.')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.');

  /// Runs the tool with [arguments] and returns a process exit code
  /// (see [ExitCodes]).
  Future<int> run(List<String> arguments) async {
    final ArgResults results;
    try {
      results = parser.parse(arguments);
    } on FormatException catch (e) {
      _logger.err(e.message);
      _printUsage();
      return ExitCodes.usage;
    }

    if (results['help'] as bool) {
      _printUsage();
      return ExitCodes.success;
    }
    if (results['version'] as bool) {
      _logger.info('flutter_trim $packageVersion');
      return ExitCodes.success;
    }
    if (results.rest.isNotEmpty) {
      _logger.err('Unexpected argument(s): ${results.rest.join(' ')}');
      _printUsage();
      return ExitCodes.usage;
    }
    if ((results['assets-only'] as bool) && (results['code-only'] as bool)) {
      _logger.err('--assets-only and --code-only cannot be used together.');
      return ExitCodes.usage;
    }
    if (results['verbose'] as bool) _logger.level = Level.verbose;

    try {
      return await _trim(results);
    } on TrimException catch (e) {
      _logger.err(e.message);
      return e.exitCode;
    } on Object catch (e, stackTrace) {
      _logger
        ..err('Unexpected error: $e')
        ..detail('$stackTrace');
      return ExitCodes.software;
    }
  }

  Future<int> _trim(ArgResults results) async {
    final root = p.normalize(p.absolute(results['path'] as String));
    if (!Directory(root).existsSync()) {
      throw TrimException(
        'Directory not found: $root',
        exitCode: ExitCodes.noInput,
      );
    }
    if (!File(p.join(root, 'pubspec.yaml')).existsSync()) {
      throw TrimException(
        'No pubspec.yaml in $root. Use --path to point at a project root.',
        exitCode: ExitCodes.noInput,
      );
    }

    final assetsOnly = results['assets-only'] as bool;
    final codeOnly = results['code-only'] as bool;
    final json = results['json'] as bool;
    final dryRun = json || (results['dry-run'] as bool);
    final failOnFindings = results['fail-on-findings'] as bool;

    final fileConfig = ConfigLoader.load(root);
    final config = fileConfig.copyWith(
      exclude: [
        ...fileConfig.exclude,
        ...(results['exclude'] as List<String>),
      ],
      scanMethods: results.wasParsed('methods')
          ? results['methods'] as bool
          : fileConfig.scanMethods,
    );

    final scanAssets = !codeOnly && config.scanAssets;
    final scanFiles = !assetsOnly && config.scanFiles;
    final scanCode = !assetsOnly && config.scanCode;

    final reporter = TrimReporter(_logger);
    if (!json) {
      reporter.printHeader(
        root: root,
        dryRun: dryRun,
        scope: [
          if (scanAssets) 'Assets',
          if (scanFiles) 'Dart files',
          if (scanCode)
            config.scanMethods ? 'Classes & methods' : 'Classes & functions',
        ],
      );
    }

    final context = _step(
      json,
      'Parsing Dart sources',
      () => ProjectContext.load(root, config: config),
      (context) => 'Parsed ${context.dartFiles.length} Dart files',
    );
    if (context.skippedFiles.isNotEmpty) {
      context.skippedFiles.forEach(
        (path, error) => _logger.detail('Skipped $path: $error'),
      );
      if (!json) {
        _logger.warn(
          '${context.skippedFiles.length} file(s) could not be read, so '
          'their references are unknown. Run with -v for details.',
        );
      }
    }

    final items = <TrimItem>[];
    if (scanAssets) {
      items.addAll(
        _step(
          json,
          'Scanning assets',
          () => AssetScanner(context).scan(),
          (found) => 'Assets: ${_count(found.length)}',
        ),
      );
    }
    var unusedFiles = <String>{};
    if (scanFiles) {
      final files = _step(
        json,
        'Following imports',
        () => FileScanner(context).scan(),
        (found) => 'Dart files: ${_count(found.length)}',
      );
      unusedFiles = {for (final item in files) item.path};
      items.addAll(files);
    }
    if (scanCode) {
      items.addAll(
        _step(
          json,
          'Scanning classes, functions & methods',
          () => CodeScanner(
            context,
            includeMethods: config.scanMethods,
            skipFiles: unusedFiles,
          ).scan(),
          (found) => 'Classes, functions & methods: ${_count(found.length)}',
        ),
      );
    }

    final findingsExit = failOnFindings && items.isNotEmpty
        ? ExitCodes.failure
        : ExitCodes.success;

    if (json) {
      _printJson(root, items);
      return findingsExit;
    }
    if (items.isEmpty) {
      reporter.printClean();
      return ExitCodes.success;
    }

    reporter.printReport(items);

    if (dryRun) {
      reporter.printDryRunDone(items.length);
      return findingsExit;
    }

    final interactive =
        _interactiveOverride ?? (stdin.hasTerminal && stdout.hasTerminal);
    if (!interactive) {
      _logger.warn(
        'No interactive terminal detected, so only the report was shown. '
        'Run ftrim in a terminal to review items one by one.',
      );
      return findingsExit;
    }

    if (!_isInsideGitRepo(root)) {
      _logger.warn(
        'This project is not under git, so deletions cannot be undone.',
      );
      if (!_logger.confirm('Continue anyway?', defaultValue: false)) {
        return ExitCodes.success;
      }
    }

    final stats = InteractivePrompt(
      logger: _logger,
      cleaner: const FileCleaner(),
    ).run(items);
    reporter.printSummary(stats);
    return stats.failed > 0 ? ExitCodes.failure : ExitCodes.success;
  }

  static String _count(int n) => n == 0 ? 'none unused' : '$n unused';

  /// Runs [action] behind a spinner (unless [quiet]) and reports [done].
  T _step<T>(
    bool quiet,
    String label,
    T Function() action,
    String Function(T result) done,
  ) {
    if (quiet) return action();
    final progress = _logger.progress(label);
    try {
      final result = action();
      progress.complete(done(result));
      return result;
    } on Object {
      progress.fail('$label failed');
      rethrow;
    }
  }

  void _printJson(String root, List<TrimItem> items) {
    final byType = <String, int>{
      for (final type in TrimItemType.values)
        type.name: items.where((item) => item.type == type).length,
    };
    final report = {
      'tool': 'flutter_trim',
      'version': packageVersion,
      'project': root,
      'summary': {
        'total': items.length,
        'sizeBytes': items.fold<int>(0, (sum, item) => sum + item.sizeBytes),
        ...byType,
      },
      'items': [for (final item in items) item.toJson()],
    };
    _logger.info(const JsonEncoder.withIndent('  ').convert(report));
  }

  static bool _isInsideGitRepo(String start) {
    var dir = Directory(start);
    while (true) {
      if (Directory(p.join(dir.path, '.git')).existsSync() ||
          File(p.join(dir.path, '.git')).existsSync()) {
        return true;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) return false;
      dir = parent;
    }
  }

  void _printUsage() {
    String heading(String text) => paint(styleBold, text);
    String example(String command, String what) =>
        '  ${paint(lightCyan, command.padRight(42))}${paint(darkGray, what)}';

    _logger.info('''
${heading('flutter_trim')} ${paint(darkGray, 'v$packageVersion')}
Find and remove unused assets, Dart files, classes, functions and methods in a
Flutter project, one item at a time.

${heading('Usage')}
  ftrim [options]

${heading('Options')}
${parser.usage.split('\n').map((line) => '  $line').join('\n')}

${heading('Examples')}
${example('ftrim', 'Review the current project interactively')}
${example('ftrim --dry-run', 'Print a report only')}
${example('ftrim -p ../my_app --assets-only', 'Only unused assets of another project')}
${example('ftrim --code-only --no-methods', 'Files, classes and functions only')}
${example('ftrim --json > report.json', 'Machine-readable report')}
${example('ftrim -n --fail-on-findings', 'Fail a CI job when anything is unused')}
${example('ftrim -e "lib/legacy/**"', 'Never report the legacy folder')}
''');
  }
}
