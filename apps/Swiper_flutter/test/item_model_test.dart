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
        'images': <Map<String, dynamic>>[
          {'url': 'https://example.com/img.jpg', 'alt': 'Sofa'}
        ],
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

    test('fromJson prioritizes selected image from image validation', () {
      final json = <String, dynamic>{
        'id': 'img-priority',
        'title': 'Sofa',
        'priceAmount': 10000,
        'images': <Map<String, dynamic>>[
          {'url': 'https://example.com/cutout.jpg'},
          {'url': 'https://example.com/lifestyle.jpg'},
        ],
        'imageValidation': <String, dynamic>{
          'selectedImageUrl': 'https://example.com/lifestyle.jpg',
        },
      };

      final item = Item.fromJson(json);
      expect(item.images.first.url, 'https://example.com/lifestyle.jpg');
      expect(item.firstImageUrl, 'https://example.com/lifestyle.jpg');
    });

    test(
        'fromJson can override selected image when analyzed metrics indicate white cutout',
        () {
      final json = <String, dynamic>{
        'id': 'img-selected-white',
        'title': 'Sofa',
        'priceAmount': 10000,
        'images': <Map<String, dynamic>>[
          {'url': 'https://example.com/white-cutout.jpg'},
          {'url': 'https://example.com/lifestyle.jpg'},
        ],
        'imageValidation': <String, dynamic>{
          'selectedImageUrl': 'https://example.com/white-cutout.jpg',
          'analyzedImages': <Map<String, dynamic>>[
            {
              'url': 'https://example.com/white-cutout.jpg',
              'valid': true,
              'sceneType': 'unknown',
              'displaySuitabilityScore': 72,
              'sceneMetrics': <String, dynamic>{
                'borderBackgroundRatio': 1.0,
                'nearWhiteRatio': 0.52,
                'textureScore': 0.02,
              },
            },
            {
              'url': 'https://example.com/lifestyle.jpg',
              'valid': true,
              'sceneType': 'unknown',
              'displaySuitabilityScore': 64,
              'sceneMetrics': <String, dynamic>{
                'borderBackgroundRatio': 0.12,
                'nearWhiteRatio': 0.02,
                'textureScore': 0.04,
              },
            },
          ],
        },
      };

      final item = Item.fromJson(json);
      expect(item.images.first.url, 'https://example.com/lifestyle.jpg');
      expect(item.firstImageUrl, 'https://example.com/lifestyle.jpg');
    });

    test(
        'fromJson falls back to contextual analyzed image when selected is missing',
        () {
      final json = <String, dynamic>{
        'id': 'img-analyzed-priority',
        'title': 'Sofa',
        'priceAmount': 10000,
        'images': <Map<String, dynamic>>[
          {'url': 'https://example.com/studio.jpg'},
          {'url': 'https://example.com/contextual.jpg'},
        ],
        'imageValidation': <String, dynamic>{
          'analyzedImages': <Map<String, dynamic>>[
            {
              'url': 'https://example.com/studio.jpg',
              'valid': true,
              'sceneType': 'studio_cutout',
              'displaySuitabilityScore': 85,
            },
            {
              'url': 'https://example.com/contextual.jpg',
              'valid': true,
              'sceneType': 'contextual',
              'displaySuitabilityScore': 70,
            },
          ],
        },
      };

      final item = Item.fromJson(json);
      expect(item.images.first.url, 'https://example.com/contextual.jpg');
      expect(item.firstImageUrl, 'https://example.com/contextual.jpg');
    });
  });
}
