/// Coerce API value to String? (avoids _JsonMap is not a subtype of String when backend sends object).
String? _string(dynamic value) {
  if (value == null) return null;
  if (value is String) return value;
  if (value is num || value is bool) return value.toString();
  return null;
}

List<String> _stringList(dynamic value) {
  if (value == null || value is! List) return [];
  return value.map((e) => _string(e)).whereType<String>().toList();
}

/// Parse DateTime from API: String (ISO) or Firestore Timestamp map (seconds/_seconds, nanoseconds/_nanoseconds).
DateTime? _parseDateTime(dynamic value) {
  if (value == null) return null;
  if (value is String) return DateTime.tryParse(value);
  if (value is Map) {
    final sec = value['seconds'] ?? value['_seconds'];
    final nano = value['nanoseconds'] ?? value['_nanoseconds'];
    if (sec != null) {
      final ms = (sec is int ? sec : (sec as num).toInt()) * 1000;
      final nanoMs = nano != null
          ? ((nano is int ? nano : (nano as num).toInt()) / 1000000).round()
          : 0;
      return DateTime.fromMillisecondsSinceEpoch(ms + nanoMs);
    }
  }
  return null;
}

/// Normalized furniture item (sofa) from Firestore/API.
class Item {
  Item({
    required this.id,
    required this.title,
    required this.priceAmount,
    this.priceCurrency = 'SEK',
    this.sourceId,
    this.sourceUrl,
    this.outboundUrl,
    this.brand,
    this.descriptionShort,
    this.dimensionsCm,
    this.sizeClass,
    this.material,
    this.colorFamily,
    this.styleTags = const [],
    this.newUsed = 'new',
    this.deliveryComplexity,
    this.smallSpaceFriendly = false,
    this.modular = false,
    this.ecoTags = const [],
    this.images = const [],
    this.lastUpdatedAt,
    this.creativeHealthScore,
    this.creativeHealthBand,
    this.creativeHealthIssues = const [],
    this.isFeatured = false,
    this.campaignId,
    this.featuredLabel,
  });

  final String id;
  final String title;
  final double priceAmount;
  final String priceCurrency;
  final String? sourceId;
  final String? sourceUrl;
  final String? outboundUrl;
  final String? brand;
  final String? descriptionShort;
  final Map<String, num>? dimensionsCm;
  final String? sizeClass;
  final String? material;
  final String? colorFamily;
  final List<String> styleTags;
  final String newUsed;
  final String? deliveryComplexity;
  final bool smallSpaceFriendly;
  final bool modular;
  final List<String> ecoTags;
  final List<ItemImage> images;
  final DateTime? lastUpdatedAt;

  // Creative Health fields (from image validation)
  final int? creativeHealthScore;
  final String? creativeHealthBand;
  final List<String> creativeHealthIssues;

  // Featured serving metadata (phase 12+; optional)
  final bool isFeatured;
  final String? campaignId;
  final String? featuredLabel;

  String? get firstImageUrl => images.isNotEmpty ? images.first.url : null;

  factory Item.fromJson(Map<String, dynamic> json) {
    final imagesRaw = json['images'] as List? ?? [];

    // Parse creative health from nested object or flat fields
    final creativeHealth = json['creativeHealth'] as Map<String, dynamic>?;
    final healthScore = creativeHealth?['score'] ?? json['creativeHealthScore'];
    final healthBand = creativeHealth?['band'] ?? json['creativeHealthBand'];
    final healthIssues =
        creativeHealth?['issues'] ?? json['creativeHealthIssues'];
    final campaignId =
        _string(json['campaignId']) ?? _string(json['campaign_id']);
    final explicitFeatured = json['isFeatured'] == true ||
        json['is_featured'] == true ||
        json['featured'] == true;

    return Item(
      id: _string(json['id']) ?? '',
      title: _string(json['title']) ?? '',
      priceAmount: (json['priceAmount'] as num?)?.toDouble() ?? 0,
      priceCurrency: _string(json['priceCurrency']) ?? 'SEK',
      sourceId: _string(json['sourceId']),
      sourceUrl: _string(json['sourceUrl']),
      outboundUrl: _string(json['outboundUrl']),
      brand: _string(json['brand']),
      descriptionShort: _string(json['descriptionShort']),
      dimensionsCm: json['dimensionsCm'] != null && json['dimensionsCm'] is Map
          ? Map<String, num>.from((json['dimensionsCm'] as Map)
              .map((k, v) => MapEntry(k.toString(), (v is num ? v : 0))))
          : null,
      sizeClass: _string(json['sizeClass']),
      material: _string(json['material']),
      colorFamily: _string(json['colorFamily']),
      styleTags: _stringList(json['styleTags']),
      newUsed: _string(json['newUsed']) ?? 'new',
      deliveryComplexity: _string(json['deliveryComplexity']),
      smallSpaceFriendly: json['smallSpaceFriendly'] == true,
      modular: json['modular'] == true,
      ecoTags: _stringList(json['ecoTags']),
      images: imagesRaw.map((e) {
        if (e is String) {
          // Handle legacy format where images are stored as plain URL strings
          return ItemImage.fromJson({'url': e});
        } else if (e is Map) {
          return ItemImage.fromJson(Map<String, dynamic>.from(e));
        } else {
          return ItemImage.fromJson(<String, dynamic>{});
        }
      }).toList(),
      lastUpdatedAt: _parseDateTime(json['lastUpdatedAt']),
      creativeHealthScore: healthScore is int
          ? healthScore
          : (healthScore is num ? healthScore.toInt() : null),
      creativeHealthBand: _string(healthBand),
      creativeHealthIssues: _stringList(healthIssues),
      isFeatured: explicitFeatured || campaignId != null,
      campaignId: campaignId,
      featuredLabel:
          _string(json['featuredLabel']) ?? _string(json['featured_label']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'priceAmount': priceAmount,
      'priceCurrency': priceCurrency,
      if (sourceId != null) 'sourceId': sourceId,
      if (sourceUrl != null) 'sourceUrl': sourceUrl,
      if (outboundUrl != null) 'outboundUrl': outboundUrl,
      if (brand != null) 'brand': brand,
      if (descriptionShort != null) 'descriptionShort': descriptionShort,
      if (dimensionsCm != null) 'dimensionsCm': dimensionsCm,
      if (sizeClass != null) 'sizeClass': sizeClass,
      if (material != null) 'material': material,
      if (colorFamily != null) 'colorFamily': colorFamily,
      'styleTags': styleTags,
      'newUsed': newUsed,
      if (deliveryComplexity != null) 'deliveryComplexity': deliveryComplexity,
      'smallSpaceFriendly': smallSpaceFriendly,
      'modular': modular,
      'ecoTags': ecoTags,
      'images': images.map((e) => e.toJson()).toList(),
      if (lastUpdatedAt != null)
        'lastUpdatedAt': lastUpdatedAt!.toIso8601String(),
      if (isFeatured) 'isFeatured': isFeatured,
      if (campaignId != null) 'campaignId': campaignId,
      if (featuredLabel != null) 'featuredLabel': featuredLabel,
    };
  }
}

class ItemImage {
  ItemImage({required this.url, this.width, this.height, this.alt, this.type});

  final String url;
  final int? width;
  final int? height;
  final String? alt;
  final String? type;

  factory ItemImage.fromJson(Map<String, dynamic> json) {
    return ItemImage(
      url: _string(json['url']) ?? '',
      width: json['width'] is int
          ? json['width'] as int
          : (json['width'] is num ? (json['width'] as num).toInt() : null),
      height: json['height'] is int
          ? json['height'] as int
          : (json['height'] is num ? (json['height'] as num).toInt() : null),
      alt: _string(json['alt']),
      type: _string(json['type']),
    );
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (alt != null) 'alt': alt,
        if (type != null) 'type': type,
      };
}
