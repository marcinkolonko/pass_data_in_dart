// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library polymer.polymer_element;

import 'dart:async';
import 'dart:html';
import 'dart:mirrors';

import 'package:observe/observe.dart';

import 'custom_element.dart';
import 'observe.dart';
import 'src/utils_observe.dart' show toCamelCase, toHyphenedName;

/**
 * Registers a [PolymerElement]. This is similar to [registerCustomElement]
 * but it is designed to work with the `<element>` element and adds additional
 * features.
 */
// TODO(sigmund): change this to take the 'localName' (recent polymer change)
void registerPolymerElement(Element elementElement, CustomElement create()) {
  // Creates the CustomElement and then publish attributes.
  createElement() {
    final CustomElement element = create();
    // TODO(jmesserly): to simplify the DWC compiler, we always emit calls to
    // registerPolymerElement, regardless of the base class type.
    if (element is PolymerElement) {
      PolymerElement pElement = element;
      pElement._parseHostEvents(elementElement);
      pElement._parseLocalEvents(elementElement);
      pElement._publishAttributes(elementElement);
    }
    return element;
  }

  registerCustomElement(elementElement.attributes['name'], createElement);
}

/**
 * *Warning*: many features of this class are not fully implemented.
 *
 * The base class for Polymer elements. It provides convience features on top
 * of the custom elements web standard.
 *
 * Currently it supports publishing attributes via:
 *
 *     <element name="..." attributes="foo, bar, baz">
 *
 * Any attribute published this way can be used in a data binding expression,
 * and it should contain a corresponding DOM field.
 *
 * *Warning*: due to dart2js mirror limititations, the mapping from HTML
 * attribute to element property is a conversion from `dash-separated-words`
 * to camelCase, rather than searching for a property with the same name.
 */
// TODO(jmesserly): fix the dash-separated-words issue. Polymer uses lowercase.
abstract class PolymerElement extends CustomElement with _EventsMixin {
  // This is a partial port of:
  // https://github.com/Polymer/polymer/blob/stable/src/attrs.js
  // https://github.com/Polymer/polymer/blob/stable/src/bindProperties.js
  // https://github.com/Polymer/polymer/blob/7936ff8/src/declaration/events.js
  // https://github.com/Polymer/polymer/blob/7936ff8/src/instance/events.js
  // TODO(jmesserly): we still need to port more of the functionality

  // TODO(sigmund): delete. The next line is only added to avoid warnings from
  // the analyzer (see http://dartbug.com/11672)
  Element get host => super.host;
  Map<String, PathObserver> _publishedAttrs;
  Map<String, StreamSubscription> _bindings;

  void _publishAttributes(Element elementElement) {
    _bindings = {};
    _publishedAttrs = {};

    var attrs = elementElement.attributes['attributes'];
    if (attrs != null) {
      // attributes='a b c' or attributes='a,b,c'
      for (var name in attrs.split(attrs.contains(',') ? ',' : ' ')) {
        name = name.trim();

        // TODO(jmesserly): PathObserver is overkill here; it helps avoid
        // "new Symbol" and other mirrors-related warnings.
        _publishedAttrs[name] = new PathObserver(this, toCamelCase(name));
      }
    }
  }

  void created() {
    // TODO(jmesserly): this breaks until we get some kind of type conversion.
    // _publishedAttrs.forEach((name, propObserver) {
    // var value = attributes[name];
    //   if (value != null) propObserver.value = value;
    // });

    _addHostListeners();
  }

  // TODO(sigmund): make this private once we create the shadow root directly
  // here in polymer element.
  void shadowRootReady(ShadowRoot root, String elementName) {
    _addInstanceListeners(root, elementName);
  }

  void bind(String name, model, String path) {
    var propObserver = _publishedAttrs[name];
    if (propObserver != null) {
      unbind(name);

      _bindings[name] = new PathObserver(model, path).bindSync((value) {
        propObserver.value = value;
      });
      return;
    }
    return super.bind(name, model, path);
  }

  void unbind(String name) {
    if (_bindings != null) {
      var binding = _bindings.remove(name);
      if (binding != null) {
        binding.cancel();
        return;
      }
    }
    return super.unbind(name);
  }

  void unbindAll() {
    for (var binding in _bindings.values) binding.cancel();
    _bindings.clear();
    return super.unbindAll();
  }
}

/**
 * Polymer features to handle the syntactic sugar on-* to declare to
 * automatically map event handlers to instance methods of the [PolymerElement].
 * This mixin is a port of:
 * https://github.com/Polymer/polymer/blob/7936ff8/src/declaration/events.js
 * https://github.com/Polymer/polymer/blob/7936ff8/src/instance/events.js
 */
abstract class _EventsMixin {
  // TODO(sigmund): implement the Dart equivalent of 'inheritDelegates'
  // Notes about differences in the implementation below:
  //  - _templateDelegates: polymer stores the template delegates directly on
  //    the template node (see in parseLocalEvents: 't.delegates = {}'). Here we
  //    simply use a separate map, where keys are the name of the
  //    custom-element.
  //  - _listenLocal we return true/false and propagate that up, JS
  //    implementation does't forward the return value.
  //  - we don't keep the side-table (weak hash map) of unhandled events (see
  //    handleIfNotHandled)
  //  - we don't use event.type to dispatch events, instead we save the event
  //    name with the event listeners. We do so to avoid translating back and
  //    forth between Dom and Dart event names.

  // ---------------------------------------------------------------------------
  // The following section was ported from:
  // https://github.com/Polymer/polymer/blob/7936ff8/src/declaration/events.js
  // ---------------------------------------------------------------------------

  /** Maps event names and their associated method in the element class. */
  final Map<String, String> _delegates = {};

  /** Expected events per element node. */
  // TODO(sigmund): investigate whether we need more than 1 set of local events
  // per element (why does the js implementation stores 1 per template node?)
  final Map<String, Set<String>> _templateDelegates =
      new Map<String, Set<String>>();

  /** [host] is needed by this mixin, but not defined here. */
  Element get host;

  /** Attribute prefix used for declarative event handlers. */
  static const _eventPrefix = 'on-';

  /** Whether an attribute declares an event. */
  static bool _isEvent(String attr) => attr.startsWith(_eventPrefix);

  /** Extracts events from the element tag attributes. */
  void _parseHostEvents(elementElement) {
    for (var attr in elementElement.attributes.keys.where(_isEvent)) {
      _delegates[toCamelCase(attr)] = elementElement.attributes[attr];
    }
  }

  /** Extracts events under the element's <template>. */
  void _parseLocalEvents(elementElement) {
    var name = elementElement.attributes["name"];
    if (name == null) return;
    var events = null;
    for (var template in elementElement.queryAll('template')) {
      var content = template.content;
      if (content != null) {
        for (var child in content.children) {
          events = _accumulateEvents(child, events);
        }
      }
    }
    if (events != null) {
      _templateDelegates[name] = events;
    }
  }

  /** Returns all events names listened by [element] and it's children. */
  static Set<String> _accumulateEvents(Element element, [Set<String> events]) {
    events = events == null ? new Set<String>() : events;

    // from: accumulateAttributeEvents, accumulateEvent
    events.addAll(element.attributes.keys.where(_isEvent).map(toCamelCase));

    // from: accumulateChildEvents
    for (var child in element.children) {
      _accumulateEvents(child, events);
    }

    // from: accumulateTemplatedEvents
    if (element.isTemplate) {
      var content = element.content;
      if (content != null) {
        for (var child in content.children) {
          _accumulateEvents(child, events);
        }
      }
    }
    return events;
  }

  // ---------------------------------------------------------------------------
  // The following section was ported from:
  // https://github.com/Polymer/polymer/blob/7936ff8/src/instance/events.js
  // ---------------------------------------------------------------------------

  /** Attaches event listeners on the [host] element. */
  void _addHostListeners() {
    for (var eventName in _delegates.keys) {
      _addNodeListener(host, eventName,
          (e) => _hostEventListener(eventName, e));
    }
  }

  void _addNodeListener(node, String onEvent, Function listener) {
    // If [node] is an element (typically when listening for host events) we
    // use directly the '.onFoo' event stream of the element instance.
    if (node is Element) {
      reflect(node).getField(new Symbol(onEvent)).reflectee.listen(listener);
      return;
    }

    // When [node] is not an element, most commonly when [node] is the
    // shadow-root of the polymer-element, we find the appropriate static event
    // stream providers and attach it to [node].
    var eventProvider = _eventStreamProviders[onEvent];
    if (eventProvider != null) {
      eventProvider.forTarget(node).listen(listener);
      return;
    }

    // When no provider is available, mainly because of custom-events, we use
    // the underlying event listeners from the DOM.
    var eventName = onEvent.substring(2).toLowerCase(); // onOneTwo => onetwo
    // Most events names in Dart match those in JS in lowercase except for some
    // few events listed in this map. We expect these cases to be handled above,
    // but just in case we include them as a safety net here.
    var jsNameFixes = const {
      'animationend': 'webkitAnimationEnd',
      'animationiteration': 'webkitAnimationIteration',
      'animationstart': 'webkitAnimationStart',
      'doubleclick': 'dblclick',
      'fullscreenchange': 'webkitfullscreenchange',
      'fullscreenerror': 'webkitfullscreenerror',
      'keyadded': 'webkitkeyadded',
      'keyerror': 'webkitkeyerror',
      'keymessage': 'webkitkeymessage',
      'needkey': 'webkitneedkey',
      'speechchange': 'webkitSpeechChange',
    };
    var fixedName = jsNameFixes[eventName];
    node.on[fixedName != null ? fixedName : eventName].listen(listener);
  }

  void _addInstanceListeners(ShadowRoot root, String elementName) {
    var events = _templateDelegates[elementName];
    if (events == null) return;
    for (var eventName in events) {
      _addNodeListener(root, eventName,
          (e) => _instanceEventListener(eventName, e));
    }
  }

  void _hostEventListener(String eventName, Event event) {
    var method = _delegates[eventName];
    if (event.bubbles && method != null) {
      _dispatchMethod(this, method, event, host);
    }
  }

  void _dispatchMethod(Object receiver, String methodName, Event event,
      Node target) {
    var detail = event is CustomEvent ? (event as CustomEvent).detail : null;
    var args = [event, detail, target];

    var method = new Symbol(methodName);
    // TODO(sigmund): consider making event listeners list all arguments
    // explicitly. Unless VM mirrors are optimized first, this reflectClass call
    // will be expensive once custom elements extend directly from Element (see
    // dartbug.com/11108).
    var methodDecl = reflectClass(receiver.runtimeType).methods[method];
    if (methodDecl != null) {
      // This will either truncate the argument list or extend it with extra
      // null arguments, so it will match the signature.
      // TODO(sigmund): consider accepting optional arguments when we can tell
      // them appart from named arguments (see http://dartbug.com/11334)
      args.length = methodDecl.parameters.where((p) => !p.isOptional).length;
    }
    reflect(receiver).invoke(method, args);
  }

  bool _instanceEventListener(String eventName, Event event) {
    if (event.bubbles) {
      if (event.path == null || !ShadowRoot.supported) {
        return _listenLocalNoEventPath(eventName, event);
      } else {
        return _listenLocal(eventName, event);
      }
    }
    return false;
  }

  bool _listenLocal(String eventName, Event event) {
    var controller = null;
    for (var target in event.path) {
      // if we hit host, stop
      if (target == host) return true;

      // find a controller for the target, unless we already found `host`
      // as a controller
      controller = (controller == host) ? controller : _findController(target);

      // if we have a controller, dispatch the event, and stop if the handler
      // returns true
      if (controller != null
          && handleEvent(controller, eventName, event, target)) {
        return true;
      }
    }
    return false;
  }

  // TODO(sorvell): remove when ShadowDOM polyfill supports event path.
  // Note that _findController will not return the expected controller when the
  // event target is a distributed node.  This is because we cannot traverse
  // from a composed node to a node in shadowRoot.
  // This will be addressed via an event path api
  // https://www.w3.org/Bugs/Public/show_bug.cgi?id=21066
  bool _listenLocalNoEventPath(String eventName, Event event) {
    var target = event.target;
    var controller = null;
    while (target != null && target != host) {
      controller = (controller == host) ? controller : _findController(target);
      if (controller != null
          && handleEvent(controller, eventName, event, target)) {
        return true;
      }
      target = target.parent;
    }
    return false;
  }

  // TODO(sigmund): investigate if this implementation is correct. Polymer looks
  // up the shadow-root that contains [node] and uses a weak-hashmap to find the
  // host associated with that root. This implementation assumes that the
  // [node] is under [host]'s shadow-root.
  Element _findController(Node node) => host.xtag;

  bool handleEvent(
      Element controller, String eventName, Event event, Element element) {
    // Note: local events are listened only in the shadow root. This dynamic
    // lookup is used to distinguish determine whether the target actually has a
    // listener, and if so, to determine lazily what's the target method.
    var methodName = element.attributes[toHyphenedName(eventName)];
    if (methodName != null) {
      _dispatchMethod(controller, methodName, event, element);
    }
    return event.bubbles;
  }
}


/** Event stream providers per event name. */
// TODO(sigmund): after dartbug.com/11108 is fixed, consider eliminating this
// table and using reflection instead.
const Map<String, EventStreamProvider> _eventStreamProviders = const {
  'onMouseWheel': Element.mouseWheelEvent,
  'onTransitionEnd': Element.transitionEndEvent,
  'onAbort': Element.abortEvent,
  'onBeforeCopy': Element.beforeCopyEvent,
  'onBeforeCut': Element.beforeCutEvent,
  'onBeforePaste': Element.beforePasteEvent,
  'onBlur': Element.blurEvent,
  'onChange': Element.changeEvent,
  'onClick': Element.clickEvent,
  'onContextMenu': Element.contextMenuEvent,
  'onCopy': Element.copyEvent,
  'onCut': Element.cutEvent,
  'onDoubleClick': Element.doubleClickEvent,
  'onDrag': Element.dragEvent,
  'onDragEnd': Element.dragEndEvent,
  'onDragEnter': Element.dragEnterEvent,
  'onDragLeave': Element.dragLeaveEvent,
  'onDragOver': Element.dragOverEvent,
  'onDragStart': Element.dragStartEvent,
  'onDrop': Element.dropEvent,
  'onError': Element.errorEvent,
  'onFocus': Element.focusEvent,
  'onInput': Element.inputEvent,
  'onInvalid': Element.invalidEvent,
  'onKeyDown': Element.keyDownEvent,
  'onKeyPress': Element.keyPressEvent,
  'onKeyUp': Element.keyUpEvent,
  'onLoad': Element.loadEvent,
  'onMouseDown': Element.mouseDownEvent,
  'onMouseMove': Element.mouseMoveEvent,
  'onMouseOut': Element.mouseOutEvent,
  'onMouseOver': Element.mouseOverEvent,
  'onMouseUp': Element.mouseUpEvent,
  'onPaste': Element.pasteEvent,
  'onReset': Element.resetEvent,
  'onScroll': Element.scrollEvent,
  'onSearch': Element.searchEvent,
  'onSelect': Element.selectEvent,
  'onSelectStart': Element.selectStartEvent,
  'onSubmit': Element.submitEvent,
  'onTouchCancel': Element.touchCancelEvent,
  'onTouchEnd': Element.touchEndEvent,
  'onTouchEnter': Element.touchEnterEvent,
  'onTouchLeave': Element.touchLeaveEvent,
  'onTouchMove': Element.touchMoveEvent,
  'onTouchStart': Element.touchStartEvent,
  'onFullscreenChange': Element.fullscreenChangeEvent,
  'onFullscreenError': Element.fullscreenErrorEvent,
  'onAutocomplete': FormElement.autocompleteEvent,
  'onAutocompleteError': FormElement.autocompleteErrorEvent,
  'onSpeechChange': InputElement.speechChangeEvent,
  'onCanPlay': MediaElement.canPlayEvent,
  'onCanPlayThrough': MediaElement.canPlayThroughEvent,
  'onDurationChange': MediaElement.durationChangeEvent,
  'onEmptied': MediaElement.emptiedEvent,
  'onEnded': MediaElement.endedEvent,
  'onLoadStart': MediaElement.loadStartEvent,
  'onLoadedData': MediaElement.loadedDataEvent,
  'onLoadedMetadata': MediaElement.loadedMetadataEvent,
  'onPause': MediaElement.pauseEvent,
  'onPlay': MediaElement.playEvent,
  'onPlaying': MediaElement.playingEvent,
  'onProgress': MediaElement.progressEvent,
  'onRateChange': MediaElement.rateChangeEvent,
  'onSeeked': MediaElement.seekedEvent,
  'onSeeking': MediaElement.seekingEvent,
  'onShow': MediaElement.showEvent,
  'onStalled': MediaElement.stalledEvent,
  'onSuspend': MediaElement.suspendEvent,
  'onTimeUpdate': MediaElement.timeUpdateEvent,
  'onVolumeChange': MediaElement.volumeChangeEvent,
  'onWaiting': MediaElement.waitingEvent,
  'onKeyAdded': MediaElement.keyAddedEvent,
  'onKeyError': MediaElement.keyErrorEvent,
  'onKeyMessage': MediaElement.keyMessageEvent,
  'onNeedKey': MediaElement.needKeyEvent,
  'onWebGlContextLost': CanvasElement.webGlContextLostEvent,
  'onWebGlContextRestored': CanvasElement.webGlContextRestoredEvent,
  'onPointerLockChange': Document.pointerLockChangeEvent,
  'onPointerLockError': Document.pointerLockErrorEvent,
  'onReadyStateChange': Document.readyStateChangeEvent,
  'onSelectionChange': Document.selectionChangeEvent,
  'onSecurityPolicyViolation': Document.securityPolicyViolationEvent,
};
