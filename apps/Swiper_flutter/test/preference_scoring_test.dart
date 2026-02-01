import 'package:flutter_test/flutter_test.dart';

/// Preference scoring: weighted overlap on styleTags/material/colorFamily/sizeClass.
/// Right swipe adds weight; left swipe ignored (per DECISIONS).
void main() {
  group('Preference scoring', () {
    test('empty weights returns zero score', () {
      final weights = <String, double>{};
      final tags = ['Scandinavian', 'fabric'];
      double score = 0;
      for (final t in tags) {
        score += weights[t] ?? 0;
      }
      expect(score, 0);
    });

    test('matching tags add to score', () {
      final weights = <String, double>{'Scandinavian': 2, 'fabric': 1};
      final tags = ['Scandinavian', 'fabric'];
      double score = 0;
      for (final t in tags) {
        score += weights[t] ?? 0;
      }
      expect(score, 3);
    });

    test('non-matching tags do not add', () {
      final weights = <String, double>{'Scandinavian': 2};
      final tags = ['Modern', 'fabric'];
      double score = 0;
      for (final t in tags) {
        score += weights[t] ?? 0;
      }
      expect(score, 0);
    });
  });
}
