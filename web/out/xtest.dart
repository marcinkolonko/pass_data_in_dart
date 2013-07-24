// Auto-generated from xtest.html.
// DO NOT EDIT.

library x_test;

import 'dart:html' as autogenerated;
import 'dart:svg' as autogenerated_svg;
import 'package:mdv/mdv.dart' as autogenerated_mdv;
import 'package:observe/observe.dart' as __observe;
import 'package:polymer/polymer.dart' as autogenerated;
import 'package:polymer/polymer.dart';
import 'package:observe/observe.dart';
import 'dart:html';



class Test extends PolymerElement with ObservableMixin
{
  /** Autogenerated from the template. */

  autogenerated.ScopedCssMapper _css;

  /** This field is deprecated, use getShadowRoot instead. */
  get _root => getShadowRoot("x-test");
  static final __shadowTemplate = new autogenerated.DocumentFragment.html('''
        <div class="test">test</div>
      ''');

  void initShadow() {
    var __root = createShadowRoot("x-test");
    shadowRootReady(__root, "x-test");
    setScopedCss("x-test", new autogenerated.ScopedCssMapper({"x-test":"[is=\"x-test\"]"}));
    _css = getScopedCss("x-test");
    if (__root is autogenerated.ShadowRoot) __root.applyAuthorStyles = true;
    __root.nodes.add(cloneTemplate(__shadowTemplate));
    autogenerated_mdv.bindModel(__root, this);
  }

  /** Original code from the component. */

  int foo;
  double bar;
  
  Test()
  {
    DivElement e = query("[is='x-test']");
    print('foo: $foo, bar: $bar');
  }
}
//# sourceMappingURL=xtest.dart.map