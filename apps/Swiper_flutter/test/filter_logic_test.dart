import 'package:flutter_test/flutter_test.dart';

/// Filter logic: sizeClass, colorFamily, newUsed applied in-memory to items.
void main() {
  group('Filter logic', () {
    test('item passes when no filters', () {
      final item = {'sizeClass': 'medium', 'colorFamily': 'gray', 'newUsed': 'new'};
      final filters = <String, dynamic>{};
      final pass = _passes(item, filters);
      expect(pass, true);
    });

    test('item passes when filter matches', () {
      final item = {'sizeClass': 'medium', 'colorFamily': 'gray', 'newUsed': 'new'};
      final filters = {'sizeClass': 'medium'};
      final pass = _passes(item, filters);
      expect(pass, true);
    });

    test('item fails when filter does not match', () {
      final item = {'sizeClass': 'medium', 'colorFamily': 'gray', 'newUsed': 'new'};
      final filters = {'sizeClass': 'small'};
      final pass = _passes(item, filters);
      expect(pass, false);
    });
  });
}

bool _passes(Map<String, dynamic> item, Map<String, dynamic> filters) {
  if (filters.containsKey('sizeClass') && item['sizeClass'] != filters['sizeClass']) return false;
  if (filters.containsKey('colorFamily') && item['colorFamily'] != filters['colorFamily']) return false;
  if (filters.containsKey('newUsed') && item['newUsed'] != filters['newUsed']) return false;
  return true;
}
