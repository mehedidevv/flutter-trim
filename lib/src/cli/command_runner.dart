import 'dart:io';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

import '../cleaners/file_cleaner.dart';
import '../models/sweep_item.dart';
import '../scanners/asset_scanner.dart';
import '../scanners/code_scanner.dart';
import '../scanners/file_scanner.dart';
import '../scanners/project_context.dart';
import '../utils/config_loader.dart';
import '../utils/logger.dart';
import '../version.dart';
import 'interactive_prompt.dart';

/// Parses CLI arguments and orchestrates scanning, reporting and cleaning.
class SweeperCommandRunner {
  /// Creates a runner.
  ///
  /// Pass a [logger] to capture or silence output, and [interactive] to force
  /// (or disable) the interactive review instead of detecting a terminal.
  SweeperCommandRunner({Logger? logger, bool? interactive})
      : _logger = logger ?? Logger(),
        _interactiveOverride = interactive;

  final Logger _logger;
  final bool? _interactiveOverride;

  /// The command-line options understood by `fsweep`.
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
      _logger.info('flutter_sweeper $packageVersion');
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
      return await _sweep(results);
    } on SweeperException catch (e) {
      _logger.err(e.message);
      return e.exitCode;
    } on Object catch (e, stackTrace) {
      _logger
        ..err('Unexpected error: $e')
        ..detail('$stackTrace');
      return ExitCodes.software;
    }
  }

  Future<int> _sweep(ArgResults results) async {
    final root = p.normalize(p.absolute(results['path'] as String));
    if (!Directory(root).existsSync()) {
      throw SweeperException(
        'Directory not found: $root',
        exitCode: ExitCodes.noInput,
      );
    }
    if (!File(p.join(root, 'pubspec.yaml')).existsSync()) {
      throw SweeperException(
        'No pubspec.yaml in $root. Use --path to point at a project root.',
        exitCode: ExitCodes.noInput,
      );
    }

    final assetsOnly = results['assets-only'] as bool;
    final codeOnly = results['code-only'] as bool;
    final dryRun = results['dry-run'] as bool;

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

    final reporter = SweepReporter(_logger)
      ..printHeader(root: root, dryRun: dryRun);

    final parsing = _logger.progress('Parsing Dart sources');
    final ProjectContext context;
    try {
      context = ProjectContext.load(root, config: config);
    } on Object {
      parsing.fail('Could not read the project');
      rethrow;
    }
    parsing.complete('Parsed ${context.dartFiles.length} Dart files');
    context.skippedFiles.forEach(
      (path, error) => _logger.detail('Skipped $path: $error'),
    );

    final items = <SweepItem>[];
    if (!codeOnly && config.scanAssets) {
      items.addAll(_scan('assets', () => AssetScanner(context).scan()));
    }
    var unusedFiles = <String>{};
    if (!assetsOnly && config.scanFiles) {
      final files = _scan('Dart files', () => FileScanner(context).scan());
      unusedFiles = {for (final item in files) item.path};
      items.addAll(files);
    }
    if (!assetsOnly && config.scanCode) {
      items.addAll(
        _scan(
          'classes, functions & methods',
          () => CodeScanner(
            context,
            includeMethods: config.scanMethods,
            skipFiles: unusedFiles,
          ).scan(),
        ),
      );
    }

    if (items.isEmpty) {
      _logger
        ..info('')
        ..success('✨ Nothing to sweep, the project is already clean.');
      return ExitCodes.success;
    }

    reporter.printReport(items);

    if (dryRun) {
      _logger.info(paint(darkGray, 'Dry run finished. Nothing was deleted.'));
      return ExitCodes.success;
    }

    final interactive =
        _interactiveOverride ?? (stdin.hasTerminal && stdout.hasTerminal);
    if (!interactive) {
      _logger.warn(
        'No interactive terminal detected, so only the report was shown. '
        'Run fsweep in a terminal to review items one by one.',
      );
      return ExitCodes.success;
    }

    _logger.info('');
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

  List<SweepItem> _scan(String label, List<SweepItem> Function() scan) {
    final progress = _logger.progress('Scanning $label');
    try {
      final found = scan();
      progress.complete('Scanned $label: ${found.length} unused');
      return found;
    } on Object {
      progress.fail('Scanning $label failed');
      rethrow;
    }
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
    _logger.info('''
${paint(styleBold, 'flutter_sweeper')} v$packageVersion
Find and remove unused assets, Dart files, classes, functions and methods in a
Flutter project, one item at a time.

${paint(styleBold, 'Usage:')} fsweep [options]

${paint(styleBold, 'Options:')}
${parser.usage}

${paint(styleBold, 'Examples:')}
  fsweep                                Review the current project interactively
  fsweep --dry-run                      Print a report only
  fsweep -p ../my_app --assets-only     Only unused assets of another project
  fsweep --code-only --no-methods       Files, classes and functions only
  fsweep -e "lib/legacy/**" -e "assets/legal/**"
''');
  }
}
