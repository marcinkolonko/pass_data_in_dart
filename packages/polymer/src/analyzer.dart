// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/**
 * Part of the template compilation that concerns with extracting information
 * from the HTML parse tree.
 */
library analyzer;

import 'package:csslib/parser.dart' as css;
import 'package:csslib/visitor.dart' show StyleSheet, treeToDebugString, Visitor, Expressions, VarDefinition;
import 'package:html5lib/dom.dart';
import 'package:html5lib/dom_parsing.dart';
import 'package:source_maps/span.dart' hide SourceFile;

import 'custom_tag_name.dart';
import 'dart_parser.dart';
import 'files.dart';
import 'html_css_fixup.dart';
import 'info.dart';
import 'messages.dart';
import 'summary.dart';
import 'utils.dart';

/**
 * Finds custom elements in this file and the list of referenced files with
 * component declarations. This is the first pass of analysis on a file.
 *
 * Adds emitted error/warning messages to [messages], if [messages] is
 * supplied.
 */
FileInfo analyzeDefinitions(GlobalInfo global, UrlInfo inputUrl,
    Document document, String packageRoot,
    Messages messages, {bool isEntryPoint: false}) {
  var result = new FileInfo(inputUrl, isEntryPoint);
  var loader = new _ElementLoader(global, result, packageRoot, messages);
  loader.visit(document);
  return result;
}

/**
 * Extract relevant information from [source] and it's children.
 * Used for testing.
 *
 * Adds emitted error/warning messages to [messages], if [messages] is
 * supplied.
 */
FileInfo analyzeNodeForTesting(Node source, Messages messages,
    {String filepath: 'mock_testing_file.html'}) {
  var result = new FileInfo(new UrlInfo(filepath, filepath, null));
  new _Analyzer(result, new IntIterator(), new GlobalInfo(), messages)
      .visit(source);
  return result;
}

/**
 *  Extract relevant information from all files found from the root document.
 *
 *  Adds emitted error/warning messages to [messages], if [messages] is
 *  supplied.
 */
void analyzeFile(SourceFile file, Map<String, FileInfo> info,
                 Iterator<int> uniqueIds, GlobalInfo global,
                 Messages messages) {
  var fileInfo = info[file.path];
  var analyzer = new _Analyzer(fileInfo, uniqueIds, global, messages);
  analyzer._normalize(fileInfo, info);
  analyzer.visit(file.document);
}


/** A visitor that walks the HTML to extract all the relevant information. */
class _Analyzer extends TreeVisitor {
  final FileInfo _fileInfo;
  LibraryInfo _currentInfo;
  Iterator<int> _uniqueIds;
  GlobalInfo _global;
  Messages _messages;

  int _generatedClassNumber = 0;

  /**
   * Whether to keep indentation spaces. Break lines and indentation spaces
   * within templates are preserved in HTML. When users specify the attribute
   * 'indentation="remove"' on a template tag, we'll trim those indentation
   * spaces that occur within that tag and its decendants. If any decendant
   * specifies 'indentation="preserve"', then we'll switch back to the normal
   * behavior.
   */
  bool _keepIndentationSpaces = true;

  _Analyzer(this._fileInfo, this._uniqueIds, this._global, this._messages) {
    _currentInfo = _fileInfo;
  }

  void visitElement(Element node) {
    if (node.tagName == 'script') {
      // We already extracted script tags in previous phase.
      return;
    }

    if (node.tagName == 'style') {
      // We've already parsed the CSS.
      // If this is a component remove the style node.
      if (_currentInfo is ComponentInfo) node.remove();
      return;
    }

    node = _bindAndReplaceElement(node);

    var lastInfo = _currentInfo;
    if (node.tagName == 'element') {
      // If element is invalid _ElementLoader already reported an error, but
      // we skip the body of the element here.
      var name = node.attributes['name'];
      if (name == null) return;

      ComponentInfo component = _fileInfo.components[name];
      if (component == null) return;

      // Associate <element> tag with its component.
      component.elementNode = node;

      _analyzeComponent(component);

      _currentInfo = component;

      // Remove the <element> tag from the tree
      node.remove();
    }

    node.attributes.forEach((name, value) {
      if (name.startsWith('on')) {
        _validateEventHandler(node, name, value);
      } else  if (name == 'pseudo' && _currentInfo is ComponentInfo) {
        // Any component's custom pseudo-element(s) defined?
        _processPseudoAttribute(node, value.split(' '));
      }
    });

    var keepSpaces = _keepIndentationSpaces;
    if (node.tagName == 'template' &&
        node.attributes.containsKey('indentation')) {
      var value = node.attributes['indentation'];
      if (value != 'remove' && value != 'preserve') {
        _messages.warning(
            "Invalid value for 'indentation' ($value). By default we preserve "
            "the indentation. Valid values are either 'remove' or 'preserve'.",
            node.sourceSpan);
      }
      _keepIndentationSpaces = value != 'remove';
    }

    // Invoke super to visit children.
    super.visitElement(node);

    _keepIndentationSpaces = keepSpaces;
    _currentInfo = lastInfo;

    if (node.tagName == 'body' || node.parent == null) {
      _fileInfo.body = node;
    }
  }

  void _analyzeComponent(ComponentInfo component) {
    component.extendsComponent = _fileInfo.components[component.extendsTag];
    if (component.extendsComponent == null &&
        isCustomTag(component.extendsTag)) {
      _messages.warning(
          'custom element with tag name ${component.extendsTag} not found.',
          component.element.sourceSpan);
    }

    // Now that the component's code has been loaded, we can validate that the
    // class exists.
    component.findClassDeclaration(_messages);
  }

  Element _bindAndReplaceElement(Element node) {
    var component = _bindCustomElement(node);
    if (component != null && node.attributes['is'] == null) {
      // We need to ensure the correct DOM element is created in the tree.
      // Until we get document.register and the browser's HTML parser can do
      // the right thing for us, we switch to the is="tag-name" form.

      var newNode = new Element.tag(component.baseExtendsTag);
      newNode.attributes['is'] = node.tagName;
      node.attributes.forEach((k, v) {
        newNode.attributes[k] = v;
      });
      newNode.nodes.addAll(node.nodes);
      node.replaceWith(newNode);
      node = newNode;
    }

    return node;
  }

  ComponentSummary _bindCustomElement(Element node) {
    // <fancy-button>
    var component = _fileInfo.components[node.tagName];
    if (component == null) {
      // TODO(jmesserly): warn for unknown element tags?

      // <button is="fancy-button">
      var componentName = node.attributes['is'];
      if (componentName != null) {
        component = _fileInfo.components[componentName];
      } else if (isCustomTag(node.tagName)) {
        componentName = node.tagName;
      }
      if (component == null && componentName != null) {
        _messages.warning(
            'custom element with tag name $componentName not found.',
            node.sourceSpan);
      }
    }
    if (component != null && !component.hasConflict) {
      _currentInfo.usedComponents[component] = true;
      return component;
    }
    return null;
  }

  void _processPseudoAttribute(Node node, List<String> values) {
    List mangledValues = [];
    for (var pseudoElement in values) {
      if (_global.pseudoElements.containsKey(pseudoElement)) continue;

      _uniqueIds.moveNext();
      var newValue = "${pseudoElement}_${_uniqueIds.current}";
      _global.pseudoElements[pseudoElement] = newValue;
      // Mangled name of pseudo-element.
      mangledValues.add(newValue);

      if (!pseudoElement.startsWith('x-')) {
        // TODO(terry): The name must start with x- otherwise it's not a custom
        //              pseudo-element.  May want to relax since components no
        //              longer need to start with x-.  See isse #509 on
        //              pseudo-element prefix.
        _messages.warning("Custom pseudo-element must be prefixed with 'x-'.",
            node.sourceSpan);
      }
    }

    // Update the pseudo attribute with the new mangled names.
    node.attributes['pseudo'] = mangledValues.join(' ');
  }

  /**
   * Support for inline event handlers that take expressions.
   * For example: `on-double-click=myHandler($event, todo)`.
   */
  void _validateEventHandler(Element node, String name, String value) {
    if (!name.startsWith('on-')) {
      // TODO(jmesserly): do we need an option to suppress this warning?
      _messages.warning('Event handler $name will be interpreted as an inline '
          'JavaScript event handler. Use the form '
          'on-event-name="handlerName" if you want a Dart handler '
          'that will automatically update the UI based on model changes.',
          node.sourceSpan);
    }

    if (value.contains('.') || value.contains('(')) {
      // TODO(sigmund): should we allow more if we use fancy-syntax?
      _messages.warning('Invalid event handler body "$value". Declare a method '
          'in your custom element "void handlerName(event, detail, target)" '
          'and use the form on-event-name="handlerName".',
          node.sourceSpan);
    }
  }

  /**
   * Normalizes references in [info]. On the [analyzeDefinitions] phase, the
   * analyzer extracted names of files and components. Here we link those names
   * to actual info classes. In particular:
   *   * we initialize the [FileInfo.components] map in [info] by importing all
   *     [declaredComponents],
   *   * we scan all [info.componentLinks] and import their
   *     [info.declaredComponents], using [files] to map the href to the file
   *     info. Names in [info] will shadow names from imported files.
   *   * we fill [LibraryInfo.externalCode] on each component declared in
   *     [info].
   */
  void _normalize(FileInfo info, Map<String, FileInfo> files) {
    _attachExtenalScript(info, files);

    for (var component in info.declaredComponents) {
      _addComponent(info, component);
      _attachExtenalScript(component, files);
    }

    for (var link in info.componentLinks) {
      var file = files[link.resolvedPath];
      // We already issued an error for missing files.
      if (file == null) continue;
      file.declaredComponents.forEach((c) => _addComponent(info, c));
    }
  }

  /**
   * Stores a direct reference in [info] to a dart source file that was loaded
   * in a script tag with the 'src' attribute.
   */
  void _attachExtenalScript(LibraryInfo info, Map<String, FileInfo> files) {
    var externalFile = info.externalFile;
    if (externalFile != null) {
      info.externalCode = files[externalFile.resolvedPath];
      if (info.externalCode != null) info.externalCode.htmlFile = info;
    }
  }

  /** Adds a component's tag name to the names in scope for [fileInfo]. */
  void _addComponent(FileInfo fileInfo, ComponentSummary component) {
    var existing = fileInfo.components[component.tagName];
    if (existing != null) {
      if (existing == component) {
        // This is the same exact component as the existing one.
        return;
      }

      if (existing is ComponentInfo && component is! ComponentInfo) {
        // Components declared in [fileInfo] shadow component names declared in
        // imported files.
        return;
      }

      if (existing.hasConflict) {
        // No need to report a second error for the same name.
        return;
      }

      existing.hasConflict = true;

      if (component is ComponentInfo) {
        _messages.error('duplicate custom element definition for '
            '"${component.tagName}".', existing.sourceSpan);
        _messages.error('duplicate custom element definition for '
            '"${component.tagName}" (second location).', component.sourceSpan);
      } else {
        _messages.error('imported duplicate custom element definitions '
            'for "${component.tagName}".', existing.sourceSpan);
        _messages.error('imported duplicate custom element definitions '
            'for "${component.tagName}" (second location).',
            component.sourceSpan);
      }
    } else {
      fileInfo.components[component.tagName] = component;
    }
  }
}

/** A visitor that finds `<link rel="import">` and `<element>` tags.  */
class _ElementLoader extends TreeVisitor {
  final GlobalInfo _global;
  final FileInfo _fileInfo;
  LibraryInfo _currentInfo;
  String _packageRoot;
  bool _inHead = false;
  Messages _messages;

  /**
   * Adds emitted warning/error messages to [_messages]. [_messages]
   * must not be null.
   */
  _ElementLoader(this._global, this._fileInfo, this._packageRoot,
      this._messages) {
    _currentInfo = _fileInfo;
  }

  void visitElement(Element node) {
    switch (node.tagName) {
      case 'link': visitLinkElement(node); break;
      case 'element': visitElementElement(node); break;
      case 'script': visitScriptElement(node); break;
      case 'head':
        var savedInHead = _inHead;
        _inHead = true;
        super.visitElement(node);
        _inHead = savedInHead;
        break;
      default: super.visitElement(node); break;
    }
  }

  /**
   * Process `link rel="import"` as specified in:
   * <https://dvcs.w3.org/hg/webcomponents/raw-file/tip/spec/components/index.html#link-type-component>
   */
  void visitLinkElement(Element node) {
    var rel = node.attributes['rel'];
    if (rel != 'component' && rel != 'components' &&
        rel != 'import' && rel != 'stylesheet') return;

    if (!_inHead) {
      _messages.warning('link rel="$rel" only valid in '
          'head.', node.sourceSpan);
      return;
    }

    if (rel == 'component' || rel == 'components') {
      _messages.warning('import syntax is changing, use '
          'rel="import" instead of rel="$rel".', node.sourceSpan);
    }

    var href = node.attributes['href'];
    if (href == null || href == '') {
      _messages.warning('link rel="$rel" missing href.',
          node.sourceSpan);
      return;
    }

    bool isStyleSheet = rel == 'stylesheet';
    var urlInfo = UrlInfo.resolve(href, _fileInfo.inputUrl, node.sourceSpan,
        _packageRoot, _messages, ignoreAbsolute: isStyleSheet);
    if (urlInfo == null) return;
    if (isStyleSheet) {
      _fileInfo.styleSheetHrefs.add(urlInfo);
    } else {
      _fileInfo.componentLinks.add(urlInfo);
    }
  }

  void visitElementElement(Element node) {
    // TODO(jmesserly): what do we do in this case? It seems like an <element>
    // inside a Shadow DOM should be scoped to that <template> tag, and not
    // visible from the outside.
    if (_currentInfo is ComponentInfo) {
      _messages.error('Nested component definitions are not yet supported.',
          node.sourceSpan);
      return;
    }

    var tagName = node.attributes['name'];
    var extendsTag = node.attributes['extends'];
    var templateNodes = node.nodes.where((n) => n.tagName == 'template');

    if (tagName == null) {
      _messages.error('Missing tag name of the component. Please include an '
          'attribute like \'name="your-tag-name"\'.',
          node.sourceSpan);
      return;
    }

    if (extendsTag == null) {
      // From the spec:
      // http://dvcs.w3.org/hg/webcomponents/raw-file/tip/spec/custom/index.html#extensions-to-document-interface
      // If PROTOTYPE is null, let PROTOTYPE be the interface prototype object
      // for the HTMLSpanElement interface.
      extendsTag = 'span';
    }

    var component = new ComponentInfo(node, _fileInfo, tagName, extendsTag);
    _fileInfo.declaredComponents.add(component);
    _addComponent(component);

    var lastInfo = _currentInfo;
    _currentInfo = component;
    super.visitElement(node);
    _currentInfo = lastInfo;
  }

  /** Adds a component's tag name to the global list. */
  void _addComponent(ComponentInfo component) {
    var existing = _global.components[component.tagName];
    if (existing != null) {
      if (existing.hasConflict) {
        // No need to report a second error for the same name.
        return;
      }

      existing.hasConflict = true;

      _messages.error('duplicate custom element definition for '
          '"${component.tagName}".', existing.sourceSpan);
      _messages.error('duplicate custom element definition for '
          '"${component.tagName}" (second location).', component.sourceSpan);
    } else {
      _global.components[component.tagName] = component;
    }
  }

  void visitScriptElement(Element node) {
    var scriptType = node.attributes['type'];
    var src = node.attributes["src"];

    if (scriptType == null) {
      // Note: in html5 leaving off type= is fine, but it defaults to
      // text/javascript. Because this might be a common error, we warn about it
      // in two cases:
      //   * an inline script tag in a web component
      //   * a script src= if the src file ends in .dart (component or not)
      //
      // The hope is that neither of these cases should break existing valid
      // code, but that they'll help component authors avoid having their Dart
      // code accidentally interpreted as JavaScript by the browser.
      if (src == null && _currentInfo is ComponentInfo) {
        _messages.warning('script tag in component with no type will '
            'be treated as JavaScript. Did you forget type="application/dart"?',
            node.sourceSpan);
      }
      if (src != null && src.endsWith('.dart')) {
        _messages.warning('script tag with .dart source file but no type will '
            'be treated as JavaScript. Did you forget type="application/dart"?',
            node.sourceSpan);
      }
      return;
    }

    if (scriptType != 'application/dart') {
      if (_currentInfo is ComponentInfo) {
        // TODO(jmesserly): this warning should not be here, but our compiler
        // does the wrong thing and it could cause surprising behavior, so let
        // the user know! See issue #340 for more info.
        // What we should be doing: leave JS component untouched by compiler.
        _messages.warning('our custom element implementation does not support '
            'JavaScript components yet. If this is affecting you please let us '
            'know at https://github.com/dart-lang/web-ui/issues/340.',
            node.sourceSpan);
      }

      return;
    }

    if (src != null) {
      if (!src.endsWith('.dart')) {
        _messages.warning('"application/dart" scripts should '
            'use the .dart file extension.',
            node.sourceSpan);
      }

      if (node.innerHtml.trim() != '') {
        _messages.error('script tag has "src" attribute and also has script '
            'text.', node.sourceSpan);
      }

      if (_currentInfo.codeAttached) {
        _tooManyScriptsError(node);
      } else {
        _currentInfo.externalFile = UrlInfo.resolve(src, _fileInfo.inputUrl,
            node.sourceSpan, _packageRoot, _messages);
      }
      return;
    }

    if (node.nodes.length == 0) return;

    // I don't think the html5 parser will emit a tree with more than
    // one child of <script>
    assert(node.nodes.length == 1);
    Text text = node.nodes[0];

    if (_currentInfo.codeAttached) {
      _tooManyScriptsError(node);
    } else if (_currentInfo == _fileInfo && !_fileInfo.isEntryPoint) {
      _messages.warning('top-level dart code is ignored on '
          ' HTML pages that define components, but are not the entry HTML '
          'file.', node.sourceSpan);
    } else {
      _currentInfo.inlinedCode = parseDartCode(
          _currentInfo.dartCodeUrl.resolvedPath, text.value, _messages,
          text.sourceSpan.start);
      if (_currentInfo.userCode.partOf != null) {
        _messages.error('expected a library, not a part.',
            node.sourceSpan);
      }
    }
  }

  void _tooManyScriptsError(Node node) {
    var location = _currentInfo is ComponentInfo ?
        'a custom element declaration' : 'the top-level HTML page';

    _messages.error('there should be only one dart script tag in $location.',
        node.sourceSpan);
  }
}


void analyzeCss(String packageRoot, List<SourceFile> files,
                Map<String, FileInfo> info, Map<String, String> pseudoElements,
                Messages messages, {warningsAsErrors: false}) {
  var analyzer = new _AnalyzerCss(packageRoot, info, pseudoElements, messages,
      warningsAsErrors);
  for (var file in files) analyzer.process(file);
  analyzer.normalize();
}

class _AnalyzerCss {
  final String packageRoot;
  final Map<String, FileInfo> info;
  final Map<String, String> _pseudoElements;
  final Messages _messages;
  final bool _warningsAsErrors;

  Set<StyleSheet> allStyleSheets = new Set<StyleSheet>();

  /**
   * [_pseudoElements] list of known pseudo attributes found in HTML, any
   * CSS pseudo-elements 'name::custom-element' is mapped to the manged name
   * associated with the pseudo-element key.
   */
  _AnalyzerCss(this.packageRoot, this.info, this._pseudoElements,
               this._messages, this._warningsAsErrors);

  /**
   * Run the analyzer on every file that is a style sheet or any component that
   * has a style tag.
   */
  void process(SourceFile file) {
    var fileInfo = info[file.path];
    if (file.isStyleSheet || fileInfo.styleSheets.length > 0) {
      var styleSheets = processVars(fileInfo);

      // Add to list of all style sheets analyzed.
      allStyleSheets.addAll(styleSheets);
    }

    // Process any components.
    for (var component in fileInfo.declaredComponents) {
      var all = processVars(component);

      // Add to list of all style sheets analyzed.
      allStyleSheets.addAll(all);
    }

    processCustomPseudoElements();
  }

  void normalize() {
    // Remove all var definitions for all style sheets analyzed.
    for (var tree in allStyleSheets) new RemoveVarDefinitions().visitTree(tree);
  }

  List<StyleSheet> processVars(var libraryInfo) {
    // Get list of all stylesheet(s) dependencies referenced from this file.
    var styleSheets = _dependencies(libraryInfo).toList();

    var errors = [];
    css.analyze(styleSheets, errors: errors, options:
      [_warningsAsErrors ? '--warnings_as_errors' : '', 'memory']);

    // Print errors as warnings.
    for (var e in errors) {
      _messages.warning(e.message, e.span);
    }

    // Build list of all var definitions.
    Map varDefs = new Map();
    for (var tree in styleSheets) {
      var allDefs = (new VarDefinitions()..visitTree(tree)).found;
      allDefs.forEach((key, value) {
        varDefs[key] = value;
      });
    }

    // Resolve all definitions to a non-VarUsage (terminal expression).
    varDefs.forEach((key, value) {
      for (var expr in (value.expression as Expressions).expressions) {
        var def = findTerminalVarDefinition(varDefs, value);
        varDefs[key] = def;
      }
    });

    // Resolve all var usages.
    for (var tree in styleSheets) new ResolveVarUsages(varDefs).visitTree(tree);

    return styleSheets;
  }

  processCustomPseudoElements() {
    var polyFiller = new PseudoElementExpander(_pseudoElements);
    for (var tree in allStyleSheets) {
      polyFiller.visitTree(tree);
    }
  }

  /**
   * Given a component or file check if any stylesheets referenced.  If so then
   * return a list of all referenced stylesheet dependencies (@imports or <link
   * rel="stylesheet" ..>).
   */
  Set<StyleSheet> _dependencies(var libraryInfo, {Set<StyleSheet> seen}) {
    if (seen == null) seen = new Set();

    // Used to resolve all pathing information.
    var inputUrl = libraryInfo is FileInfo
        ? libraryInfo.inputUrl
        : (libraryInfo as ComponentInfo).declaringFile.inputUrl;

    for (var styleSheet in libraryInfo.styleSheets) {
      if (!seen.contains(styleSheet)) {
        // TODO(terry): VM uses expandos to implement hashes.  Currently, it's a
        //              linear (not constant) time cost (see dartbug.com/5746).
        //              If this bug isn't fixed and performance show's this a
        //              a problem we'll need to implement our own hashCode or
        //              use a different key for better perf.
        // Add the stylesheet.
        seen.add(styleSheet);

        // Any other imports in this stylesheet?
        var urlInfos = findImportsInStyleSheet(styleSheet, packageRoot,
            inputUrl, _messages);

        // Process other imports in this stylesheets.
        for (var importSS in urlInfos) {
          var importInfo = info[importSS.resolvedPath];
          if (importInfo != null) {
            // Add all known stylesheets processed.
            seen.addAll(importInfo.styleSheets);
            // Find dependencies for stylesheet referenced with a
            // @import
            for (var ss in importInfo.styleSheets) {
              var urls = findImportsInStyleSheet(ss, packageRoot, inputUrl,
                  _messages);
              for (var url in urls) {
                _dependencies(info[url.resolvedPath], seen: seen);
              }
            }
          }
        }
      }
    }

    return seen;
  }
}
