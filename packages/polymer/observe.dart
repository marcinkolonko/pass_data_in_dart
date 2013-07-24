// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/**
 * Helpers for observable objects.
 * Intended for use with `package:mdv_observe`.
 */
library polymer.observe;

import 'dart:async';
// TODO(jmesserly): PathObserver should be in mdv_observe.
import 'dart:html' show PathObserver;
import 'package:observe/observe.dart';

/**
 * Use `@observable` to make a property observable.
 * The overhead will be minimal unless they are actually being observed.
 */
const observable = const _ObservableAnnotation();

/**
 * The type of the `@observable` annotation.
 *
 * Library private because you should be able to use the [observable] field
 * to get the one and only instance. We could make it public though, if anyone
 * needs it for some reason.
 */
class _ObservableAnnotation {
  const _ObservableAnnotation();
}

// Inspired by ArrayReduction at:
// https://raw.github.com/rafaelw/ChangeSummary/master/util/array_reduction.js
// The main difference is we support anything on the rich Dart Iterable API.

const _VALUE = const Symbol('value');

/**
 * Forwards an observable property from one object to another. For example:
 *
 *     class MyModel extends ObservableBase {
 *       StreamSubscription _sub;
 *       MyOtherModel _otherModel;
 *
 *       MyModel() {
 *         ...
 *         _sub = bindProperty(_otherModel, const Symbol('value'),
 *             () => notifyProperty(this, const Symbol('prop'));
 *       }
 *
 *       String get prop => _otherModel.value;
 *       set prop(String value) { _otherModel.value = value; }
 *     }
 *
 * See also [notifyProperty].
 */
StreamSubscription bindProperty(Observable source, Symbol sourceName,
    void callback()) {
  return source.changes.listen((records) {
    for (var record in records) {
      if (record.changes(sourceName)) {
        callback();
      }
    }
  });
}

/**
 * Notify the property change. Shorthand for:
 *
 *     target.notifyChange(new PropertyChangeRecord(targetName));
 */
void notifyProperty(ObservableMixin target, Symbol targetName) {
  target.notifyChange(new PropertyChangeRecord(targetName));
}


/**
 * Observes a path starting from each item in the list.
 */
class ListPathObserver<E, P> extends ObservableBase {
  final ObservableList<E> list;
  final String _itemPath;
  final List<PathObserver> _observers = <PathObserver>[];
  final List<StreamSubscription> _subs = <StreamSubscription>[];
  StreamSubscription _sub;
  bool _scheduled = false;
  Iterable<P> _value;

  ListPathObserver(this.list, String path)
      : _itemPath = path {

    _sub = list.changes.listen((records) {
      for (var record in records) {
        if (record is ListChangeRecord) {
          _observeItems(record.addedCount - record.removedCount);
        }
      }
      _scheduleReduce(null);
    });

    _observeItems(list.length);
    _reduce();
  }

  Iterable<P> get value => _value;

  void dispose() {
    if (_sub != null) _sub.cancel();
    _subs.forEach((s) => s.cancel());
    _subs.clear();
  }

  void _reduce() {
    _scheduled = false;
    _value = _observers.map((o) => o.value);
    notifyChange(new PropertyChangeRecord(_VALUE));
  }

  void _scheduleReduce(_) {
    if (_scheduled) return;
    _scheduled = true;
    queueChangeRecords(_reduce);
  }

  _observeItems(int lengthAdjust) {
    if (lengthAdjust > 0) {
      for (int i = 0; i < lengthAdjust; i++) {
        int len = _observers.length;
        var pathObs = new PathObserver(list, '$len.$_itemPath');
        _subs.add(pathObs.values.listen(_scheduleReduce));
        _observers.add(pathObs);
      }
    } else if (lengthAdjust < 0) {
      for (int i = 0; i < -lengthAdjust; i++) {
        _subs.removeLast().cancel();
      }
      int len = _observers.length;
      _observers.removeRange(len + lengthAdjust, len);
    }
  }

  setValueWorkaround(key, value) {}
  getValueWorkaround(key) => key == _VALUE ? value : null;
}
