// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library polymer.event;

import 'dart:html';
import 'custom_element.dart';

/**
 * *Warning*: this is an implementation helper and should not be used in your
 * code. This method will be replaced in favor of calling to the handler
 * via mirrors.
 *
 * Register an event handler.
 */
void registerEventHandler(String query, void registerEvent(Node node)) {
  if (_eventHandlers == null) {
    _eventHandlers = {};
    CustomElement.templateCreated.add(_hookEvents);
  }
  if (_eventHandlers.containsKey(query)) {
    throw new ArgumentError('duplicate event handler selector $query');
  }
  _eventHandlers[query] = registerEvent;
}

void _hookEvents(DocumentFragment fragment) {
  _eventHandlers.forEach((query, hookEvent) {
    for (var node in fragment.queryAll(query)) {
      hookEvent(node);
    }
  });
}

Map<String, Function> _eventHandlers;
