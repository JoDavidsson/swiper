import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'event_tracker.dart';

/// Wraps the app and observes lifecycle to flush event buffer and emit session_end / session_resume.
class EventTrackerLifecycleObserver extends ConsumerStatefulWidget {
  const EventTrackerLifecycleObserver({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<EventTrackerLifecycleObserver> createState() => _EventTrackerLifecycleObserverState();
}

class _EventTrackerLifecycleObserverState extends ConsumerState<EventTrackerLifecycleObserver>
    with WidgetsBindingObserver {
  DateTime? _lastBackgroundedAt;
  static const _resumeThresholdMs = 30000;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final tracker = ref.read(eventTrackerProvider);
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _lastBackgroundedAt = DateTime.now();
      tracker.track('session_end', {});
      tracker.flush();
    } else if (state == AppLifecycleState.resumed) {
      if (_lastBackgroundedAt != null &&
          DateTime.now().difference(_lastBackgroundedAt!).inMilliseconds >= _resumeThresholdMs) {
        tracker.track('session_resume', {});
      }
      _lastBackgroundedAt = null;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
