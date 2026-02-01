// Web: capture window.onerror and unhandledrejection for integration tests.

import 'dart:html' as html;

final List<String> _captured = [];

List<String> get capturedErrors => List.unmodifiable(_captured);

void installConsoleCapture() {
  _captured.clear();
  html.window.onError.listen((html.Event event) {
    final ev = event as html.ErrorEvent;
    _captured.add('${ev.message}');
  });
  // unhandledrejection: use addEventListener (onUnhandledRejection not in dart:html Window).
  html.window.addEventListener('unhandledrejection', (html.Event event) {
    final ev = event as html.PromiseRejectionEvent;
    _captured.add(ev.reason?.toString() ?? 'unhandledrejection');
  });
}

void clearCapturedErrors() {
  _captured.clear();
}
