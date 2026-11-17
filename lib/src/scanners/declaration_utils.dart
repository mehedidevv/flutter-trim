import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/syntactic_entity.dart';
import 'package:analyzer/dart/ast/token.dart';

import '../models/trim_item.dart';

/// Shared AST helpers used by [CodeScanner] and [FileCleaner] so that the
/// scanner and the cleaner always agree on what a declaration is.
///
/// Only AST APIs that exist in every supported `analyzer` major version
/// (6.x through 14.x) are used here. Class and enum names are read from the
/// token after the `class` / `enum` keyword, and members are found by walking
/// [AstNode.childEntities], because `ClassDeclaration.name`, `.members` and
/// `NamedCompilationUnitMember` were removed in analyzer 11.
abstract final class DeclarationUtils {
  /// Name used for extensions declared without a name.
  static const String unnamedExtension = '<unnamed extension>';

  /// The declared name of a top-level member, or `null` if unnamed.
  static String? nameOf(CompilationUnitMember member) {
    if (member is ClassDeclaration) return _nameAfter(member.classKeyword);
    if (member is EnumDeclaration) return _nameAfter(member.enumKeyword);
    if (member is MixinDeclaration) return member.name.lexeme;
    if (member is TypeAlias) return member.name.lexeme;
    if (member is FunctionDeclaration) return member.name.lexeme;
    if (member is ExtensionDeclaration) return member.name?.lexeme;
    return null;
  }

  /// The reportable kind of a top-level member, or `null` when the member is
  /// never reported on its own (extensions, variables, getters/setters).
  static DeclarationKind? kindOf(CompilationUnitMember member) {
    if (member is ClassDeclaration || member is ClassTypeAlias) {
      return DeclarationKind.classDeclaration;
    }
    if (member is MixinDeclaration) return DeclarationKind.mixinDeclaration;
    if (member is EnumDeclaration) return DeclarationKind.enumDeclaration;
    if (member is TypeAlias) return DeclarationKind.typedefDeclaration;
    if (member is FunctionDeclaration && !member.isGetter && !member.isSetter) {
      return DeclarationKind.function;
    }
    return null;
  }

  /// Name of a member that can contain methods, or `null` if it cannot.
  static String? containerNameOf(CompilationUnitMember member) {
    if (member is ClassDeclaration ||
        member is MixinDeclaration ||
        member is EnumDeclaration) {
      return nameOf(member);
    }
    if (member is ExtensionDeclaration) {
      return member.name?.lexeme ?? unnamedExtension;
    }
    return null;
  }

  /// Class-level members of a container (empty for non-containers).
  static List<ClassMember> membersOf(CompilationUnitMember member) {
    if (containerNameOf(member) == null) return const [];
    final members = <ClassMember>[];
    void visit(SyntacticEntity entity) {
      if (entity is ClassMember) {
        members.add(entity);
      } else if (entity is AstNode) {
        entity.childEntities.forEach(visit);
      }
    }

    member.childEntities.forEach(visit);
    return members;
  }

  /// Whether [metadata] contains an annotation called [name].
  static bool hasAnnotation(List<Annotation> metadata, String name) =>
      metadata.any((annotation) => annotation.name.name == name);

  /// Finds the AST node described by [item] in [unit], or `null`.
  static AnnotatedNode? locate(CompilationUnit unit, TrimItem item) {
    for (final member in unit.declarations) {
      if (item.kind == DeclarationKind.method) {
        if (containerNameOf(member) != item.parentName) continue;
        for (final method in membersOf(member).whereType<MethodDeclaration>()) {
          if (method.name.lexeme == item.name) return method;
        }
      } else if (kindOf(member) == item.kind && nameOf(member) == item.name) {
        return member;
      }
    }
    return null;
  }

  /// The first identifier after [keyword], skipping modifiers such as the
  /// `const` of a primary constructor (`class const Point(...)`).
  static String? _nameAfter(Token keyword) {
    Token? token = keyword.next;
    while (token != null && !token.isEof) {
      if (token.isIdentifier) return token.lexeme;
      token = token.next;
    }
    return null;
  }
}
