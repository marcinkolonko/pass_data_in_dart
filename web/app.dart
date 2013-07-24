import 'package:mdv/mdv.dart' as mdv;
import 'package:fancy_syntax/syntax.dart';
import 'dart:html';

void main() {
  mdv.initialize();
  TemplateElement.syntax['fancy'] = new FancySyntax();
  
  query("#temp").model = null;
}
