// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/**
 * Code transform for @observable. The core transformation is relatively
 * straightforward, and essentially like an editor refactoring. You can find the
 * core implementation in [transformClass], which is ultimately called by
 * [transformObservables], the entry point to this library.
 */
library observable_transform;

import 'package:analyzer_experimental/src/generated/ast.dart';
import 'package:analyzer_experimental/src/generated/error.dart';
import 'package:analyzer_experimental/src/generated/scanner.dart';
import 'package:source_maps/span.dart' show SourceFile;
import 'dart_parser.dart';
import 'messages.dart';
import 'refactor.dart';

/**
 * Transform types in Dart [userCode] marked with `@observable` by hooking all
 * field setters, and notifying the observation system of the change. If the
 * code was changed this returns true, otherwise returns false. Modified code
 * can be found in [userCode.code].
 *
 * Note: there is no special checking for transitive immutability. It is up to
 * the rest of the observation system to handle check for this condition and
 * handle it appropriately. We do not want to violate reference equality of
 * any fields that are set into the object.
 */
TextEditTransaction transformObservables(DartCodeInfo userCode,
    Messages messages) {

  if (userCode == null || userCode.compilationUnit == null) return null;
  var transaction = new TextEditTransaction(userCode.code, userCode.sourceFile);
  transformCompilationUnit(userCode, transaction, messages);
  return transaction;
}

void transformCompilationUnit(DartCodeInfo userCode, TextEditTransaction code,
    Messages messages) {

  var unit = userCode.compilationUnit;
  for (var directive in unit.directives) {
    if (directive is LibraryDirective && hasObservable(directive)) {
      messages.warning('@observable on a library no longer has any effect. '
          'It should be placed on individual fields.',
          _getSpan(userCode.sourceFile, directive));
      break;
    }
  }

  for (var declaration in unit.declarations) {
    if (declaration is ClassDeclaration) {
      transformClass(declaration, code, userCode.sourceFile, messages);
    } else if (declaration is TopLevelVariableDeclaration) {
      if (hasObservable(declaration)) {
        messages.warning('Top-level fields can no longer be observable. '
            'Observable fields should be put in an observable objects.',
            _getSpan(userCode.sourceFile, declaration));
      }
    }
  }
}

_getSpan(SourceFile file, ASTNode node) => file.span(node.offset, node.end);

/** True if the node has the `@observable` annotation. */
bool hasObservable(AnnotatedNode node) => hasAnnotation(node, 'observable');

bool hasAnnotation(AnnotatedNode node, String name) {
  // TODO(jmesserly): this isn't correct if the annotation has been imported
  // with a prefix, or cases like that. We should technically be resolving, but
  // that is expensive.
  return node.metadata.any((m) => m.name.name == name &&
      m.constructorName == null && m.arguments == null);
}

void transformClass(ClassDeclaration cls, TextEditTransaction code,
    SourceFile file, Messages messages) {

  if (hasObservable(cls)) {
    messages.warning('@observable on a class no longer has any effect. '
        'It should be placed on individual fields.',
        _getSpan(file, cls));
  }

  // Track fields that were transformed.
  var instanceFields = new Set<String>();
  var getters = new List<String>();
  var setters = new List<String>();

  for (var member in cls.members) {
    if (member is FieldDeclaration) {
      bool isStatic = hasKeyword(member.keyword, Keyword.STATIC);
      if (isStatic) {
        if (hasObservable(member)){
          messages.warning('Static fields can no longer be observable. '
              'Observable fields should be put in an observable objects.',
              _getSpan(file, member));
        }
        continue;
      }
      if (hasObservable(member)) {
        transformFields(member.fields, code, member.offset, member.end);

        var names = member.fields.variables.map((v) => v.name.name);

        getters.addAll(names);
        if (!_isReadOnly(member.fields)) {
          setters.addAll(names);
          instanceFields.addAll(names);
        }
      }
    }
    // TODO(jmesserly): this is a temporary workaround until we can remove
    // getValueWorkaround and setValueWorkaround.
    if (member is MethodDeclaration) {
      if (hasKeyword(member.propertyKeyword, Keyword.GET)) {
        getters.add(member.name.name);
      } else if (hasKeyword(member.propertyKeyword, Keyword.SET)) {
        setters.add(member.name.name);
      }
    }
  }

  // If nothing was @observable, bail.
  if (instanceFields.length == 0) return;

  if (getters.length > 0 || setters.length > 0) {
    mirrorWorkaround(cls, code, getters, setters);
  }

  // Fix initializers, because they aren't allowed to call the setter.
  for (var member in cls.members) {
    if (member is ConstructorDeclaration) {
      fixConstructor(member, code, instanceFields);
    }
  }
}


/**
 * Generates `getValueWorkaround` and `setValueWorkaround`. These will go away
 * shortly once dart2js supports mirrors. For the moment they provide something
 * that the binding system can use.
 */
void mirrorWorkaround(ClassDeclaration cls, TextEditTransaction code,
    List<String> getters, List<String> setters) {

  var sb = new StringBuffer('\ngetValueWorkaround(key) {\n');
  for (var name in getters) {
    if (name.startsWith('_')) continue;
    sb.write("  if (key == const Symbol('$name')) return this.$name;\n");
  }
  sb.write('  return null;\n}\n');
  sb.write('\nsetValueWorkaround(key, value) {\n');
  for (var name in setters) {
    if (name.startsWith('_')) continue;
    sb.write("  if (key == const Symbol('$name')) "
        "{ this.$name = value; return; }\n");
  }
  sb.write('}\n');

  int pos = cls.rightBracket.offset;
  var indent = guessIndent(code.original, pos);

  code.edit(pos, pos, sb.toString().replaceAll('\n', '\n$indent  '));
}

bool hasKeyword(Token token, Keyword keyword) =>
    token is KeywordToken && (token as KeywordToken).keyword == keyword;

String getOriginalCode(TextEditTransaction code, ASTNode node) =>
    code.original.substring(node.offset, node.end);

void fixConstructor(ConstructorDeclaration ctor, TextEditTransaction code,
    Set<String> changedFields) {

  // Fix normal initializers
  for (var initializer in ctor.initializers) {
    if (initializer is ConstructorFieldInitializer) {
      var field = initializer.fieldName;
      if (changedFields.contains(field.name)) {
        code.edit(field.offset, field.end, '__\$${field.name}');
      }
    }
  }

  // Fix "this." initializer in parameter list. These are tricky:
  // we need to preserve the name and add an initializer.
  // Preserving the name is important for named args, and for dartdoc.
  // BEFORE: Foo(this.bar, this.baz) { ... }
  // AFTER:  Foo(bar, baz) : __$bar = bar, __$baz = baz { ... }

  var thisInit = [];
  for (var param in ctor.parameters.parameters) {
    if (param is DefaultFormalParameter) {
      param = param.parameter;
    }
    if (param is FieldFormalParameter) {
      var name = param.identifier.name;
      if (changedFields.contains(name)) {
        thisInit.add(name);
        // Remove "this." but keep everything else.
        code.edit(param.thisToken.offset, param.period.end, '');
      }
    }
  }

  if (thisInit.length == 0) return;

  // TODO(jmesserly): smarter formatting with indent, etc.
  var inserted = thisInit.map((i) => '__\$$i = $i').join(', ');

  int offset;
  if (ctor.separator != null) {
    offset = ctor.separator.end;
    inserted = ' $inserted,';
  } else {
    offset = ctor.parameters.end;
    inserted = ' : $inserted';
  }

  code.edit(offset, offset, inserted);
}

bool _isReadOnly(VariableDeclarationList fields) {
  return hasKeyword(fields.keyword, Keyword.CONST) ||
      hasKeyword(fields.keyword, Keyword.FINAL);
}

void transformFields(VariableDeclarationList fields, TextEditTransaction code,
    int begin, int end) {

  if (_isReadOnly(fields)) return;

  var indent = guessIndent(code.original, begin);
  var replace = new StringBuffer();

  // Unfortunately "var" doesn't work in all positions where type annotations
  // are allowed, such as "var get name". So we use "dynamic" instead.
  var type = 'dynamic';
  if (fields.type != null) {
    type = getOriginalCode(code, fields.type);
  }

  for (var field in fields.variables) {
    var initializer = '';
    if (field.initializer != null) {
      initializer = ' = ${getOriginalCode(code, field.initializer)}';
    }

    var name = field.name.name;

    // TODO(jmesserly): should we generate this one one line, so source maps
    // don't break?
    if (replace.length > 0) replace.write('\n\n$indent');
    replace.write('''
$type __\$$name$initializer;
$type get $name => __\$$name;
set $name($type value) {
  __\$$name = notifyPropertyChange(const Symbol('$name'), __\$$name, value);
}
'''.replaceAll('\n', '\n$indent'));
  }

  code.edit(begin, end, '$replace');
}
