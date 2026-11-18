import 'dart:convert';

import 'package:analyzer/dart/ast/ast.dart';

import '../models/trim_item.dart';
import 'declaration_utils.dart';
import 'project_context.dart';

/// Uses the Dart `analyzer` AST to find classes, mixins, enums, typedefs,
/// top-level functions, methods, top-level variables and fields that are
/// never referenced.
///
/// Declarations are collected from the AST of every reportable file in
/// `lib/`. References are the identifier tokens of *every* Dart file in the
/// project (including tests and generated code), so a declaration is unused
/// only when its name appears nowhere outside its own body. Self references
/// (constructors, recursion, `static Foo of(...)`) therefore do not keep a
/// declaration alive.
///
/// The check is name based and deliberately conservative: two declarations
/// that share a name keep each other alive, which can hide dead code but
/// never reports used code.
class CodeScanner {
  /// Creates a scanner for [context].
  CodeScanner(
    this.context, {
    this.includeMethods = true,
    this.includeVariables = true,
    this.skipFiles = const {},
  });

  /// The project being scanned.
  final ProjectContext context;

  /// Whether methods inside used classes are reported as well.
  final bool includeMethods;

  /// Whether top-level variables and class fields are reported as well.
  final bool includeVariables;

  /// Absolute paths whose declarations are not reported (for example files
  /// already reported as unused by [FileScanner]).
  final Set<String> skipFiles;

  /// Annotations that mark a declaration as used by reflection, native code
  /// or the VM.
  static const Set<String> _protectedAnnotations = {'pragma', 'protected'};

  /// Methods that frameworks call by convention or that tooling invokes
  /// dynamically.
  static const Set<String> _conventionalMethods = {
    'main',
    'call',
    'build',
    'createState',
    'initState',
    'dispose',
    'didChangeDependencies',
    'didUpdateWidget',
    'deactivate',
    'activate',
    'reassemble',
    'debugFillProperties',
    'didChangeAppLifecycleState',
    'toString',
    'noSuchMethod',
    'toJson',
    'fromJson',
    'toMap',
    'fromMap',
    'props',
  };

  /// Returns every unused declaration, sorted by path and line.
  List<TrimItem> scan() {
    final usages = _indexUsages();
    final containers = <_Candidate>[];
    final topLevel = <_Candidate>[];
    final methods = <_Candidate>[];

    for (final file in context.dartFiles) {
      if (!file.relativePath.startsWith('lib/')) continue;
      if (file.isIgnored || skipFiles.contains(file.path)) continue;
      if (!context.filter.canReport(file.relativePath)) continue;
      _collect(file, topLevel, containers, methods);
    }

    bool isUsed(_Candidate candidate) {
      final occurrences = usages[candidate.name];
      if (occurrences == null) return false;
      return occurrences.any((usage) => !candidate.contains(usage));
    }

    final unusedContainers = <_Candidate>{};
    final items = <TrimItem>[];
    for (final candidate in topLevel) {
      if (isUsed(candidate)) continue;
      if (candidate.isContainer) unusedContainers.add(candidate);
      items.add(candidate.toItem());
    }
    for (final method in methods) {
      // Methods and fields of an unused class disappear with the class.
      if (unusedContainers.contains(method.parent)) continue;
      if (!isUsed(method)) items.add(method.toItem());
    }

    items.sort((a, b) {
      final byPath = a.relativePath.compareTo(b.relativePath);
      return byPath != 0 ? byPath : (a.lineNumber ?? 0) - (b.lineNumber ?? 0);
    });
    return items;
  }

  Map<String, List<_Usage>> _indexUsages() {
    final usages = <String, List<_Usage>>{};
    for (final file in context.dartFiles) {
      for (final token in file.identifiers) {
        usages
            .putIfAbsent(token.lexeme, () => [])
            .add(_Usage(file.path, token.offset));
      }
    }
    return usages;
  }

  void _collect(
    ParsedDartFile file,
    List<_Candidate> topLevel,
    List<_Candidate> containers,
    List<_Candidate> methods,
  ) {
    for (final member in file.unit.declarations) {
      final kind = DeclarationUtils.kindOf(member);
      final name = DeclarationUtils.nameOf(member);
      _Candidate? container;

      final wanted = kind != DeclarationKind.variable || includeVariables;
      if (kind != null &&
          name != null &&
          wanted &&
          _isReportable(file, member, name)) {
        final candidate = _Candidate(
          file: file,
          node: member,
          name: name,
          kind: kind,
          isContainer: DeclarationUtils.containerNameOf(member) != null,
        );
        topLevel.add(candidate);
        if (candidate.isContainer) {
          container = candidate;
          containers.add(candidate);
        }
      }

      final containerName = DeclarationUtils.containerNameOf(member);
      if (containerName == null) continue;
      if (DeclarationUtils.hasAnnotation(member.metadata, 'pragma')) continue;

      if (includeVariables) {
        final fields =
            DeclarationUtils.membersOf(member).whereType<FieldDeclaration>();
        for (final field in fields) {
          final fieldName = DeclarationUtils.fieldNameOf(field);
          if (fieldName == null ||
              _hasModifier(field, const {'abstract', 'external'}) ||
              DeclarationUtils.hasAnnotation(field.metadata, 'override') ||
              !_isReportable(file, field, fieldName)) {
            continue;
          }
          methods.add(
            _Candidate(
              file: file,
              node: field,
              name: fieldName,
              kind: DeclarationKind.field,
              parentName: containerName,
              parent: container,
            ),
          );
        }
      }

      if (!includeMethods) continue;
      final memberMethods =
          DeclarationUtils.membersOf(member).whereType<MethodDeclaration>();
      for (final method in memberMethods) {
        final methodName = method.name.lexeme;
        if (method.isOperator ||
            method.isGetter ||
            method.isSetter ||
            // Abstract (and external) methods have an empty `;` body.
            // `isAbstract` is deprecated in newer analyzer versions.
            method.body is EmptyFunctionBody ||
            method.externalKeyword != null ||
            _conventionalMethods.contains(methodName) ||
            DeclarationUtils.hasAnnotation(method.metadata, 'override') ||
            !_isReportable(file, method, methodName)) {
          continue;
        }
        methods.add(
          _Candidate(
            file: file,
            node: method,
            name: methodName,
            kind: DeclarationKind.method,
            parentName: containerName,
            parent: container,
          ),
        );
      }
    }
  }

  /// Whether a modifier in [keywords] appears before the field's type/name.
  static bool _hasModifier(FieldDeclaration field, Set<String> keywords) {
    var token = field.firstTokenAfterCommentAndMetadata;
    final stop = field.fields.variables.first.name;
    while (token != stop && !token.isEof) {
      if (keywords.contains(token.lexeme)) return true;
      token = token.next!;
    }
    return false;
  }

  bool _isReportable(ParsedDartFile file, Declaration node, String name) {
    if (name == 'main' || context.config.keep.contains(name)) return false;
    if (node.metadata.any(
      (annotation) => _protectedAnnotations.contains(annotation.name.name),
    )) {
      return false;
    }
    return !_hasKeepMarker(file, node);
  }

  /// `// flutter_trim:keep` on the line above (or in the doc comment of)
  /// a declaration protects it.
  static bool _hasKeepMarker(ParsedDartFile file, Declaration node) {
    final content = file.content;
    final declarationStart = node.firstTokenAfterCommentAndMetadata.offset;
    var regionStart = node.offset;
    // Include the line directly above the node's first token.
    final previousLineEnd =
        regionStart > 0 ? content.lastIndexOf('\n', regionStart - 1) : -1;
    if (previousLineEnd > 0) {
      regionStart = content.lastIndexOf('\n', previousLineEnd - 1) + 1;
    }
    return content
        .substring(regionStart, declarationStart)
        .contains(keepMarker);
  }
}

class _Usage {
  const _Usage(this.path, this.offset);

  final String path;
  final int offset;
}

class _Candidate {
  _Candidate({
    required this.file,
    required this.node,
    required this.name,
    required this.kind,
    this.parentName,
    this.parent,
    this.isContainer = false,
  });

  final ParsedDartFile file;
  final Declaration node;
  final String name;
  final DeclarationKind kind;
  final String? parentName;
  final _Candidate? parent;
  final bool isContainer;

  int get start => node.offset;
  int get end => node.end;

  /// Whether [usage] lies inside this declaration's own source range.
  bool contains(_Usage usage) =>
      usage.path == file.path && usage.offset >= start && usage.offset < end;

  TrimItem toItem() {
    final nameOffset = node.firstTokenAfterCommentAndMetadata.offset;
    final source = file.content.substring(start, end);
    return TrimItem(
      type: TrimItemType.declaration,
      path: file.path,
      relativePath: file.relativePath,
      name: name,
      kind: kind,
      parentName: parentName,
      lineNumber: file.lineOf(nameOffset),
      sizeBytes: utf8.encode(source).length,
      reason: switch (kind) {
        DeclarationKind.method =>
          'Method is never called or torn off anywhere in the project',
        DeclarationKind.field =>
          'Field is never read, written or initialized anywhere',
        DeclarationKind.variable =>
          'Variable is never read or written anywhere in the project',
        _ => 'No references outside its own declaration',
      },
    );
  }
}
