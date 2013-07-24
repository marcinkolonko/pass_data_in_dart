// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library polymer.custom_syntax;

import 'dart:html';

// TODO(jmesserly): implement missing features here or in dart:html directly,
// such as:
//   * various DOM properties not supported by MDV, such as <option> selected
//     item, <textarea> value.
//   * SafeHtml (can we even support this with current bindings?)
//   * SafeUri
//   * indentation=remove
//   * ... anything else?
class _ExtraSyntax extends CustomBindingSyntax {
  getBinding(model, String path, name, node) {
    return super.getBinding(model, path, name, node);
  }
}

/**
 * Provides extra syntax in templates. This currently supports:
 *
 *   - Dart event handlers
 */
final CustomBindingSyntax webUISyntax = new _ExtraSyntax();
