import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:flutter_sweeper/flutter_sweeper.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Builds a small Flutter-like project on disk. Nothing is resolved, so the
/// fixture does not need the Flutter SDK.
Directory createFixture({String? sweeperConfig}) {
  final root = Directory.systemTemp.createTempSync('flutter_sweeper_test_');

  void write(String relative, String content) {
    final file = File(p.joinAll([root.path, ...relative.split('/')]));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  write('pubspec.yaml', '''
name: demo_app
environment:
  sdk: '>=3.0.0 <4.0.0'
dependencies:
  flutter:
    sdk: flutter
flutter_launcher_icons:
  image_path: assets/icon/app_icon.png
flutter:
  assets:
    - assets/images/
    - assets/data/config.json
    - assets/icon/
  fonts:
    - family: Roboto
      fonts:
        - asset: assets/fonts/Roboto-Regular.ttf
''');
  if (sweeperConfig != null) write('flutter_sweeper.yaml', sweeperConfig);

  // Assets.
  write('assets/images/logo.png', 'png');
  write('assets/images/2.0x/logo.png', 'png@2x');
  write('assets/images/old_banner.png', 'unused banner');
  write('assets/images/avatar.png', 'dynamic');
  write('assets/data/config.json', '{}');
  write('assets/icon/app_icon.png', 'icon');
  write('assets/fonts/Roboto-Regular.ttf', 'font');
  write('assets/raw/orphan.txt', 'undeclared and unused');
  write('assets/images/.DS_Store', 'junk');

  // Dart sources.
  write('lib/main.dart', '''
import 'package:flutter/material.dart';
import 'package:demo_app/widgets/home.dart';

void main() => runApp(const Home());
''');
  write('lib/widgets/home.dart', '''
import 'package:flutter/material.dart';
import '../services/used_service.dart';

const imagesDir = 'assets/images';

class Home extends StatelessWidget {
  const Home({super.key});

  @override
  Widget build(BuildContext context) {
    UsedService().fetch();
    Image.asset('\$imagesDir/avatar.png');
    return Image.asset('assets/images/logo.png');
  }
}

/// A widget nobody uses any more.
class UnusedWidget extends StatelessWidget {
  const UnusedWidget({super.key});

  static UnusedWidget create() => const UnusedWidget();

  @override
  Widget build(BuildContext context) => const SizedBox();
}

String unusedHelper() => 'x';

// flutter_sweeper:keep
String keptHelper() => 'kept';

@pragma('vm:entry-point')
void backgroundCallback() {}
''');
  write('lib/services/used_service.dart', '''
class UsedService {
  void fetch() {
    _load('assets/data/config.json');
  }

  void _load(String path) {}

  void neverCalled() {
    neverCalled();
  }
}

extension StringX on String {
  String shout() => toUpperCase();
}
''');
  write('lib/legacy/old_screen.dart', '''
part 'old_screen.g.dart';

class OldScreen {}
''');
  write('lib/legacy/old_screen.g.dart', '''
part of 'old_screen.dart';

class _\$OldScreen {}
''');
  write('lib/models/user.g.dart', '// generated, never reported\n');
  write('test/home_test.dart', '''
import 'package:demo_app/main.dart' as app;

void main() => app.main();
''');

  return root;
}

void main() {
  late Directory root;
  late ProjectContext context;

  setUp(() {
    root = createFixture();
    context = ProjectContext.load(root.path);
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('AssetScanner', () {
    test('reports declared and undeclared unused assets only', () {
      final found =
          AssetScanner(context).scan().map((i) => i.relativePath).toSet();

      expect(found, {
        'assets/images/old_banner.png',
        'assets/raw/orphan.txt',
      });
    });

    test('marks declaration status in the reason', () {
      final items = {
        for (final item in AssetScanner(context).scan()) item.name: item,
      };
      expect(items['old_banner.png']!.reason, contains('Declared'));
      expect(items['orphan.txt']!.reason, contains('Not declared'));
    });

    test('respects exclude globs', () {
      final filtered = ProjectContext.load(
        root.path,
        config: const SweeperConfig(exclude: ['assets/raw/**']),
      );
      final found = AssetScanner(filtered).scan().map((i) => i.relativePath);
      expect(found, isNot(contains('assets/raw/orphan.txt')));
      expect(found, contains('assets/images/old_banner.png'));
    });

    test('derives flutter_gen getter names', () {
      expect(AssetScanner.flutterGenName('ic_home-active.png'), 'icHomeActive');
      expect(AssetScanner.flutterGenName('logo.png'), 'logo');
    });
  });

  group('FileScanner', () {
    test('reports unreachable libraries with their part files', () {
      final items = FileScanner(context).scan();

      expect(items.map((i) => i.relativePath), ['lib/legacy/old_screen.dart']);
      expect(
        items.single.companionPaths.map(p.basename),
        ['old_screen.g.dart'],
      );
    });

    test('honours configured entry points', () {
      final configured = ProjectContext.load(
        root.path,
        config: const SweeperConfig(
          entryPoints: ['lib/legacy/old_screen.dart'],
        ),
      );
      expect(FileScanner(configured).scan(), isEmpty);
    });
  });

  group('CodeScanner', () {
    List<SweepItem> scanCode({bool methods = true}) {
      final unusedFiles = {
        for (final item in FileScanner(context).scan()) item.path,
      };
      return CodeScanner(
        context,
        includeMethods: methods,
        skipFiles: unusedFiles,
      ).scan();
    }

    test('finds unused classes, functions and methods', () {
      final names = scanCode().map((i) => i.displayName).toSet();

      expect(names, {
        'UnusedWidget',
        'unusedHelper',
        'UsedService.neverCalled',
        'StringX.shout',
      });
    });

    test('does not report used, protected or overridden declarations', () {
      final names = scanCode().map((i) => i.displayName).toSet();

      const protected = [
        'Home',
        'UsedService',
        'UsedService.fetch',
        'UsedService._load',
        'keptHelper',
        'backgroundCallback',
        'main',
        'OldScreen',
        // Methods of an unused class are not listed separately.
        'UnusedWidget.create',
      ];
      for (final name in protected) {
        expect(names, isNot(contains(name)), reason: name);
      }
    });

    test('can skip methods', () {
      final kinds = scanCode(methods: false).map((i) => i.kind).toSet();
      expect(kinds, isNot(contains(DeclarationKind.method)));
    });

    test('records line numbers', () {
      final widget =
          scanCode().firstWhere((item) => item.name == 'UnusedWidget');
      expect(widget.relativePath, 'lib/widgets/home.dart');
      expect(widget.lineNumber, 18);
    });
  });

  group('FileCleaner', () {
    test('removes a class with its doc comment and keeps the file valid', () {
      final item = CodeScanner(context)
          .scan()
          .firstWhere((item) => item.name == 'UnusedWidget');

      final result = const FileCleaner().clean(item);
      final content = File(item.path).readAsStringSync();

      expect(result.success, isTrue);
      expect(result.bytesFreed, greaterThan(0));
      expect(content, isNot(contains('UnusedWidget')));
      expect(content, isNot(contains('A widget nobody uses')));
      expect(content, contains('class Home'));
      expect(
        parseString(content: content, throwIfDiagnostics: false).errors,
        isEmpty,
      );
    });

    test('removes a single method', () {
      final item = CodeScanner(context)
          .scan()
          .firstWhere((item) => item.displayName == 'UsedService.neverCalled');

      expect(const FileCleaner().clean(item).success, isTrue);
      final content = File(item.path).readAsStringSync();
      expect(content, isNot(contains('neverCalled')));
      expect(content, contains('void _load'));
    });

    test('deletes a Dart file together with its parts', () {
      final item = FileScanner(context).scan().single;

      expect(const FileCleaner().clean(item).success, isTrue);
      expect(File(item.path).existsSync(), isFalse);
      expect(File(item.companionPaths.single).existsSync(), isFalse);
    });

    test('dry run leaves files untouched', () {
      final item = AssetScanner(context).scan().first;

      expect(const FileCleaner(dryRun: true).clean(item).success, isTrue);
      expect(File(item.path).existsSync(), isTrue);
    });

    test('reports a failure when the item is already gone', () {
      final item = AssetScanner(context).scan().first;
      File(item.path).deleteSync();
      expect(const FileCleaner().clean(item).success, isFalse);
    });

    test('removeRange collapses the surrounding blank line', () {
      const source = 'a();\n\nvoid b() {}\n\nc();\n';
      final start = source.indexOf('void');
      final end = source.indexOf('}') + 1;
      expect(FileCleaner.removeRange(source, start, end), 'a();\n\nc();\n');
    });
  });

  group('ConfigLoader', () {
    test('reads flutter_sweeper.yaml', () {
      final configured = createFixture(
        sweeperConfig: '''
exclude:
  - lib/legacy/**
keep:
  - UnusedWidget
scan:
  methods: false
''',
      );
      addTearDown(() => configured.deleteSync(recursive: true));

      final config = ConfigLoader.load(configured.path);
      expect(config.exclude, ['lib/legacy/**']);
      expect(config.keep, {'UnusedWidget'});
      expect(config.scanMethods, isFalse);
      expect(config.scanAssets, isTrue);

      final ctx = ProjectContext.load(configured.path, config: config);
      expect(FileScanner(ctx).scan(), isEmpty);
      expect(
        CodeScanner(ctx, includeMethods: config.scanMethods)
            .scan()
            .map((i) => i.name),
        isNot(contains('UnusedWidget')),
      );
    });
  });

  group('SweeperCommandRunner', () {
    test('prints the version', () async {
      final runner = SweeperCommandRunner(logger: Logger(level: Level.quiet));
      expect(await runner.run(['--version']), ExitCodes.success);
    });

    test('rejects conflicting flags', () async {
      final runner = SweeperCommandRunner(logger: Logger(level: Level.quiet));
      expect(
        await runner.run(['--assets-only', '--code-only']),
        ExitCodes.usage,
      );
    });

    test('dry run reports without deleting', () async {
      final runner = SweeperCommandRunner(
        logger: Logger(level: Level.quiet),
        interactive: false,
      );
      expect(
        await runner.run(['--path', root.path, '--dry-run']),
        ExitCodes.success,
      );
      expect(
        File(p.join(root.path, 'assets', 'images', 'old_banner.png'))
            .existsSync(),
        isTrue,
      );
    });

    test('fails cleanly without a pubspec', () async {
      final empty = Directory.systemTemp.createTempSync('fsweep_empty_');
      addTearDown(() => empty.deleteSync(recursive: true));
      final runner = SweeperCommandRunner(logger: Logger(level: Level.quiet));
      expect(await runner.run(['-p', empty.path]), ExitCodes.noInput);
    });
  });

  group('DeclarationUtils', () {
    test('reads names after class modifiers and finds members', () {
      File(p.join(root.path, 'lib', 'widgets', 'shapes.dart'))
          .writeAsStringSync('''
abstract base class UnusedShape {
  double area();
  void unusedDraw() {}
}

sealed class UnusedResult {}

enum UnusedColor {
  red;

  void unusedPaint() {}
}

mixin UnusedMixin {}

typedef UnusedCallback = void Function();
''');
      // Import it from main.dart so the file itself is reachable.
      final mainFile = File(p.join(root.path, 'lib', 'main.dart'));
      mainFile.writeAsStringSync(
        "import 'widgets/shapes.dart';\n${mainFile.readAsStringSync()}",
      );

      final names = CodeScanner(ProjectContext.load(root.path))
          .scan()
          .where((i) => i.relativePath == 'lib/widgets/shapes.dart')
          .map((i) => '${i.kind!.name}:${i.displayName}')
          .toSet();

      expect(names, {
        'classDeclaration:UnusedShape',
        'classDeclaration:UnusedResult',
        'enumDeclaration:UnusedColor',
        'mixinDeclaration:UnusedMixin',
        'typedefDeclaration:UnusedCallback',
      });
    });

    test('reports methods of used containers but never abstract ones', () {
      File(p.join(root.path, 'lib', 'widgets', 'shape.dart'))
          .writeAsStringSync('''
abstract class Shape {
  double area();
  void unusedDraw() {}
}
''');
      File(p.join(root.path, 'lib', 'main.dart')).writeAsStringSync('''
import 'widgets/shape.dart';

Shape? shape;
void main() => shape?.toString();
''');

      final names = CodeScanner(ProjectContext.load(root.path))
          .scan()
          .map((i) => i.displayName)
          .toSet();
      expect(names, contains('Shape.unusedDraw'));
      expect(names, isNot(contains('Shape.area')));
    });
  });

  test('packageVersion matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version =
        RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec)!;
    expect(packageVersion, version.group(1));
  });
}
