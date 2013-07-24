// Auto-generated from index.html.
// DO NOT EDIT.

library index_html;

import 'dart:html' as autogenerated;
import 'dart:svg' as autogenerated_svg;
import 'package:mdv/mdv.dart' as autogenerated_mdv;
import 'package:observe/observe.dart' as __observe;
import 'package:polymer/polymer.dart' as autogenerated;
import 'xmycomponent.dart';
import 'package:mdv/mdv.dart' as mdv;
import 'package:fancy_syntax/syntax.dart';
import 'dart:html';


// Original code


void main() {
  mdv.initialize();
  TemplateElement.syntax['fancy'] = new FancySyntax();
  
  query("#temp").model = null;
}

// Additional generated code
void init_autogenerated() {
  autogenerated.registerPolymerElement(new autogenerated.Element.html('<element name="x-my-component" constructor="MyComponent" extends="div" attributes="foo bar" apply-author-styles="">\n      <template>\n        <div>foo: {{foo}}, bar: {{bar}}</div>\n      </template>\n      <script type="application/dart" src="xmycomponent.dart"></script>\n    </element>'), () => new MyComponent());
}

//# sourceMappingURL=app.dart.map