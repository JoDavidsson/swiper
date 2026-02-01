import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:integration_test/integration_test.dart';
import 'package:swiper_flutter/app.dart';

// Conditional import: web captures console errors; other platforms use stub.
import 'console_capture_stub.dart' if (dart.library.html) 'console_capture_web.dart' as console_capture;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Swiper integration', () {
    testWidgets('navigate away while deck is loading - no dispose error', (WidgetTester tester) async {
      // Capture console errors (on web) before any async work.
      console_capture.installConsoleCapture();

      await Hive.initFlutter();
      await tester.pumpWidget(const ProviderScope(child: SwiperApp()));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Go to deck (starts session + deck load).
      await tester.tap(find.text('Skip to swipe'));
      await tester.pump(const Duration(milliseconds: 100));

      // Navigate away before deck load completes (Likes in bottom nav).
      await tester.tap(find.text('Likes'));
      await tester.pump(const Duration(seconds: 2));

      final errors = console_capture.capturedErrors;
      final disposeRelated = errors.where((String e) {
        final lower = e.toLowerCase();
        return lower.contains('dispose') || lower.contains('tried to use');
      }).toList();

      expect(
        disposeRelated,
        isEmpty,
        reason: 'Console had dispose-related errors: $disposeRelated. All captured: $errors',
      );
    });
  });
}
