// Auto-generated from xmycomponent.html.
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
        <div>foo: {{foo}}, bar: {{bar}}</div>
      ''');

  void initShadow() {
    var __root = createShadowRoot("x-my-component");
    shadowRootReady(__root, "x-my-component");
    setScopedCss("x-my-component", new autogenerated.ScopedCssMapper({"x-my-component":"[is=\"x-my-component\"]"}));
    _css = getScopedCss("x-my-component");
    if (__root is autogenerated.ShadowRoot) __root.applyAuthorStyles = true;
    __root.nodes.add(cloneTemplate(__shadowTemplate));
    autogenerated_mdv.bindModel(__root, this);
  }

  /** Original code from the component. */

  int __$foo;
  int get foo => __$foo;
  set foo(int value) {
    __$foo = notifyPropertyChange(const Symbol('foo'), __$foo, value);
  }
  
  double __$bar;
  double get bar => __$bar;
  set bar(double value) {
    __$bar = notifyPropertyChange(const Symbol('bar'), __$bar, value);
  }
  
  
  MyComponent()
  {
  }
  
  void inserted()
  {
    print("foo: $foo, bar: $bar");
  }

  getValueWorkaround(key) {
    if (key == const Symbol('foo')) return this.foo;
    if (key == const Symbol('bar')) return this.bar;
    return null;
  }
  
  setValueWorkaround(key, value) {
    if (key == const Symbol('foo')) { this.foo = value; return; }
    if (key == const Symbol('bar')) { this.bar = value; return; }
  }
  }
//# sourceMappingURL=xmycomponent.dart.map