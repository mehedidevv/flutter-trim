/// The category of a finding produced by one of the scanners.
enum TrimItemType {
  /// A file under an asset folder or declared in `pubspec.yaml`.
  asset('Asset'),

  /// A `.dart` file in `lib/` that no reachable library imports.
  file('Dart file'),

  /// A class, mixin, enum, typedef, top-level function or method.
  declaration('Declaration');

  const TrimItemType(this.label);

  /// Human readable label.
  final String label;
}

/// The kind of Dart declaration for [TrimItemType.declaration] items.
enum DeclarationKind {
  /// A `class` declaration or a `class X = Y with Z;` alias.
  classDeclaration('Class'),

  /// A `mixin` declaration.
  mixinDeclaration('Mixin'),

  /// An `enum` declaration.
  enumDeclaration('Enum'),

  /// A `typedef` declaration.
  typedefDeclaration('Typedef'),

  /// A top-level function (not a getter or setter).
  function('Function'),

  /// A method inside a class, mixin, enum or extension.
  method('Method');

  const DeclarationKind(this.label);

  /// Human readable label.
  final String label;
}

/// A single unused thing the user can keep or delete.
class TrimItem {
  /// Creates a finding. Scanners build these; you rarely need to.
  const TrimItem({
    required this.type,
    required this.path,
    required this.relativePath,
    required this.name,
    required this.sizeBytes,
    required this.reason,
    this.lineNumber,
    this.kind,
    this.parentName,
    this.companionPaths = const [],
  });

  /// What sort of finding this is.
  final TrimItemType type;

  /// Absolute path of the file that holds (or is) the item.
  final String path;

  /// Project-relative path using `/` separators.
  final String relativePath;

  /// File name for assets/files, identifier for declarations.
  final String name;

  /// Bytes that deleting this item would free.
  final int sizeBytes;

  /// Why the scanner considers this item unused.
  final String reason;

  /// 1-based line of the declaration name (declarations only).
  final int? lineNumber;

  /// Declaration kind (declarations only).
  final DeclarationKind? kind;

  /// Enclosing class/mixin/enum/extension for methods.
  final String? parentName;

  /// Extra absolute paths deleted together with this item
  /// (for example `part` files such as `foo.g.dart`).
  final List<String> companionPaths;

  /// Short label such as `Asset`, `Dart file`, `Class` or `Method`.
  String get typeLabel => kind?.label ?? type.label;

  /// [name], prefixed with `Parent.` for methods.
  String get displayName => parentName == null ? name : '$parentName.$name';

  /// `relative/path.dart:line` for declarations, the relative path otherwise.
  String get location =>
      lineNumber == null ? relativePath : '$relativePath:$lineNumber';

  /// Whether this item is a declaration inside a Dart file rather than a
  /// whole file.
  bool get isDeclaration => type == TrimItemType.declaration;

  /// A JSON-encodable representation, for machine-readable reports.
  Map<String, Object?> toJson() => {
        'type': type.name,
        'kind': kind?.name,
        'name': name,
        'parent': parentName,
        'path': relativePath,
        'line': lineNumber,
        'sizeBytes': sizeBytes,
        'reason': reason,
        if (companionPaths.isNotEmpty) 'companions': companionPaths.length,
      };

  @override
  String toString() => '$typeLabel $displayName ($location)';
}

/// Process exit codes (sysexits.h conventions).
abstract final class ExitCodes {
  /// Everything went fine (including dry runs and a clean project).
  static const int success = 0;

  /// At least one deletion failed, or `--fail-on-findings` found something.
  static const int failure = 1;

  /// The command line was invalid.
  static const int usage = 64;

  /// The project folder or its `pubspec.yaml` was not found.
  static const int noInput = 66;

  /// An unexpected internal error occurred.
  static const int software = 70;

  /// `flutter_trim.yaml` is invalid.
  static const int config = 78;
}

/// A recoverable, user-facing error.
class TrimException implements Exception {
  /// Creates an error that ends the run with [exitCode].
  const TrimException(this.message, {this.exitCode = ExitCodes.software});

  /// Message shown to the user.
  final String message;

  /// Process exit code to use (see [ExitCodes]).
  final int exitCode;

  @override
  String toString() => 'TrimException: $message';
}
