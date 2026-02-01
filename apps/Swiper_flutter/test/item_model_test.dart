import 'package:flutter_test/flutter_test.dart';
import 'package:swiper_flutter/data/models/item.dart';

void main() {
  group('Item model', () {
    test('fromJson parses minimal item', () {
      final json = <String, dynamic>{
        'id': 'abc',
        'title': 'Sofa',
        'priceAmount': 9990,
        'priceCurrency': 'SEK',
      };
      final item = Item.fromJson(json);
      expect(item.id, 'abc');
      expect(item.title, 'Sofa');
      expect(item.priceAmount, 9990);
      expect(item.priceCurrency, 'SEK');
      expect(item.images, isEmpty);
    });

    test('fromJson parses with optional fields', () {
      final json = <String, dynamic>{
        'id': 'x',
        'title': 'Sofa',
        'priceAmount': 10000,
        'images': <Map<String, dynamic>>[{'url': 'https://example.com/img.jpg', 'alt': 'Sofa'}],
        'sizeClass': 'medium',
        'material': 'fabric',
      };
      final item = Item.fromJson(json);
      expect(item.images.length, 1);
      expect(item.images.first.url, 'https://example.com/img.jpg');
      expect(item.sizeClass, 'medium');
      expect(item.material, 'fabric');
      expect(item.firstImageUrl, 'https://example.com/img.jpg');
    });

    test('fromJson handles missing fields gracefully', () {
      final json = <String, dynamic>{};
      final item = Item.fromJson(json);
      expect(item.id, '');
      expect(item.title, '');
      expect(item.priceAmount, 0);
      expect(item.styleTags, isEmpty);
    });
  });
}
