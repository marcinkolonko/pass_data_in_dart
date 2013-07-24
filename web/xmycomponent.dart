import 'package:polymer/polymer.dart';
import 'package:observe/observe.dart';
import 'dart:html';

class MyComponent extends PolymerElement with ObservableMixin
{
  @observable int foo;
  @observable double bar;
  
  MyComponent()
  {
  }
  
  void inserted()
  {
    print("foo: $foo, bar: $bar");
  }
}