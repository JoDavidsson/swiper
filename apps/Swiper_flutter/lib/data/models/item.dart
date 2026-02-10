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
    this.primaryCategory,
    this.sofaTypeShape,
    this.sofaFunction,
    this.seatCountBucket,
    this.environment,
    this.subCategory,
    this.roomTypes = const [],
    // Rich furniture specs
    this.seatHeightCm,
    this.seatDepthCm,
    this.seatWidthCm,
    this.seatCount,
    this.weightKg,
    this.frameMaterial,
    this.coverMaterial,
    this.legMaterial,
    this.cushionFilling,
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

  // Classification axes
  final String? primaryCategory;
  final String? sofaTypeShape;
  final String? sofaFunction;
  final String? seatCountBucket;
  final String? environment;
  final String? subCategory;
  final List<String> roomTypes;

  // Rich furniture specs
  final double? seatHeightCm;
  final double? seatDepthCm;
  final double? seatWidthCm;
  final int? seatCount;
  final double? weightKg;
  final String? frameMaterial;
  final String? coverMaterial;
  final String? legMaterial;
  final String? cushionFilling;

  /// Whether this item has any rich specification data.
  bool get hasSpecs =>
      seatHeightCm != null ||
      seatDepthCm != null ||
      seatWidthCm != null ||
      seatCount != null ||
      weightKg != null ||
      frameMaterial != null ||
      coverMaterial != null ||
      legMaterial != null ||
      cushionFilling != null;

  String? get firstImageUrl => images.isNotEmpty ? images.first.url : null;
  bool get hasValidPrice => priceAmount > 0;
  String priceLabel({String missingLabel = 'Price N/A'}) => hasValidPrice
      ? '${priceAmount.toStringAsFixed(0)} $priceCurrency'
      : missingLabel;

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
      primaryCategory: _string(json['primaryCategory']),
      sofaTypeShape: _string(json['sofaTypeShape']),
      sofaFunction: _string(json['sofaFunction']),
      seatCountBucket: _string(json['seatCountBucket']),
      environment: _string(json['environment']),
      subCategory: _string(json['subCategory']),
      roomTypes: _stringList(json['roomTypes']),
      // Rich furniture specs (also look in facets map as fallback)
      seatHeightCm: (json['seatHeightCm'] as num?)?.toDouble() ??
          ((json['facets'] as Map?)?['sitthojd'] as num?)?.toDouble(),
      seatDepthCm: (json['seatDepthCm'] as num?)?.toDouble() ??
          ((json['facets'] as Map?)?['sittdjup'] as num?)?.toDouble(),
      seatWidthCm: (json['seatWidthCm'] as num?)?.toDouble() ??
          ((json['facets'] as Map?)?['sittbredd'] as num?)?.toDouble(),
      seatCount: (json['seatCount'] as num?)?.toInt(),
      weightKg: (json['weightKg'] as num?)?.toDouble(),
      frameMaterial: _string(json['frameMaterial']),
      coverMaterial: _string(json['coverMaterial']),
      legMaterial: _string(json['legMaterial']),
      cushionFilling: _string(json['cushionFilling']),
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
      if (primaryCategory != null) 'primaryCategory': primaryCategory,
      if (sofaTypeShape != null) 'sofaTypeShape': sofaTypeShape,
      if (sofaFunction != null) 'sofaFunction': sofaFunction,
      if (seatCountBucket != null) 'seatCountBucket': seatCountBucket,
      if (environment != null) 'environment': environment,
      if (subCategory != null) 'subCategory': subCategory,
      if (roomTypes.isNotEmpty) 'roomTypes': roomTypes,
      if (seatHeightCm != null) 'seatHeightCm': seatHeightCm,
      if (seatDepthCm != null) 'seatDepthCm': seatDepthCm,
      if (seatWidthCm != null) 'seatWidthCm': seatWidthCm,
      if (seatCount != null) 'seatCount': seatCount,
      if (weightKg != null) 'weightKg': weightKg,
      if (frameMaterial != null) 'frameMaterial': frameMaterial,
      if (coverMaterial != null) 'coverMaterial': coverMaterial,
      if (legMaterial != null) 'legMaterial': legMaterial,
      if (cushionFilling != null) 'cushionFilling': cushionFilling,
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
