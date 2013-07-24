// Auto-generated from xwebcomponent.html.
// DO NOT EDIT.

library x_my_component;

import 'dart:html' as autogenerated;
import 'dart:svg' as autogenerated_svg;
import 'package:mdv/mdv.dart' as autogenerated_mdv;
import 'package:observe/observe.dart' as __observe;
import 'package:polymer/polymer.dart' as autogenerated;
import 'package:polymer/polymer.dart';
import 'package:observe/observe.dart';
import 'dart:html';



class MyComponent extends PolymerElement with ObservableMixin
{
  /** Autogenerated from the template. */

  autogenerated.ScopedCssMapper _css;

  /** This field is deprecated, use getShadowRoot instead. */
  get _root => getShadowRoot("x-my-component");
  static final __shadowTemplate = new autogenerated.DocumentFragment.html('''
        <div>string: \${{string}}</div>
      ''');

  void initShadow() {
    var __root = createShadowRoot("x-my-component");
    shadowRootReady(__root, "x-my-component");
    setScopedCss("x-my-component", new autogenerated.ScopedCssMapper({"x-my-component":"[is=\"x-my-component\"]"}));
    _css = getScopedCss("x-my-component");
    __root.nodes.add(cloneTemplate(__shadowTemplate));
    autogenerated_mdv.bindModel(__root, this, autogenerated.TemplateElement.syntax['fancy']);
  }

  /** Original code from the component. */

  int foo = 10;
  double bar = 10.1;
  String string;
  
  MyComponent()
  {
  }
  
  void inserted()
  {
    print(string);
    print("foo: $foo, bar: $bar");
  }
}
//# sourceMappingURL=xwebcomponent.dart.map