/// Coerce API value to String? (avoids _JsonMap is not a subtype of String when backend sends object).
String? _string(dynamic value) {
  if (value == null) return null;
  if (value is String) return value;
  if (value is num || value is bool) return value.toString();
  return null;
}

String _decodeHtmlEntities(String input) {
  var out = input;
  const entities = {
    '&nbsp;': ' ',
    '&amp;': '&',
    '&quot;': '"',
    '&apos;': "'",
    '&#39;': "'",
    '&lt;': '<',
    '&gt;': '>',
    '&ouml;': 'ö',
    '&Ouml;': 'Ö',
    '&auml;': 'ä',
    '&Auml;': 'Ä',
    '&aring;': 'å',
    '&Aring;': 'Å',
  };
  entities.forEach((key, value) {
    out = out.replaceAll(key, value);
  });

  out = out.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
    final code = int.tryParse(m.group(1) ?? '');
    if (code == null) return m.group(0) ?? '';
    return String.fromCharCode(code);
  });
  out = out.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
    final code = int.tryParse(m.group(1) ?? '', radix: 16);
    if (code == null) return m.group(0) ?? '';
    return String.fromCharCode(code);
  });
  return out;
}

String? _cleanTitle(dynamic value) {
  final raw = _string(value);
  if (raw == null) return null;
  var text = raw.trim();
  if (text.isEmpty) return null;
  for (var i = 0; i < 3; i++) {
    final decoded = _decodeHtmlEntities(text);
    if (decoded == text) break;
    text = decoded;
  }
  text = text.replaceAll(RegExp(r'<[^>]+>', dotAll: true), ' ');
  text = _decodeHtmlEntities(text);
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return text.isEmpty ? null : text;
}

List<String> _stringList(dynamic value) {
  if (value == null || value is! List) return [];
  return value.map((e) => _string(e)).whereType<String>().toList();
}

Map<String, dynamic>? _map(dynamic value) {
  if (value == null) return null;
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((k, v) => MapEntry(k.toString(), v));
  }
  return null;
}

double? _double(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

double _clamp01(double value) {
  if (value < 0) return 0;
  if (value > 1) return 1;
  return value;
}

double _analyzedImageRankScore(Map<String, dynamic> row) {
  final sceneType = _string(row['sceneType']) ?? 'unknown';
  final displaySuitability = _double(row['displaySuitabilityScore']) ?? 0;
  final sceneMetrics = _map(row['sceneMetrics']) ?? const <String, dynamic>{};
  final borderBackgroundRatio =
      _clamp01(_double(sceneMetrics['borderBackgroundRatio']) ?? 0);
  final nearWhiteRatio = _clamp01(_double(sceneMetrics['nearWhiteRatio']) ?? 0);
  final textureScore = _clamp01(_double(sceneMetrics['textureScore']) ?? 0);

  var score = displaySuitability;
  if (sceneType == 'contextual') score += 18;
  if (sceneType == 'studio_cutout') score -= 25;

  // Strongly penalize likely studio/cutout frames even when sceneType is unknown.
  if (borderBackgroundRatio > 0.7) {
    score -= (borderBackgroundRatio - 0.7) * 40;
  }
  if (nearWhiteRatio > 0.25) {
    score -= (nearWhiteRatio - 0.25) * 30;
  }
  if (textureScore < 0.03 && borderBackgroundRatio > 0.75) {
    score -= 10;
  }

  return score;
}

String? _bestAnalyzedImageUrl(dynamic analyzedRaw) {
  if (analyzedRaw is! List) return null;

  String? bestUrl;
  var bestScore = double.negativeInfinity;

  for (final entry in analyzedRaw) {
    final row = _map(entry);
    if (row == null) continue;
    if (row['valid'] != true) continue;

    final url = _string(row['url'])?.trim();
    if (url == null || url.isEmpty) continue;

    final score = _analyzedImageRankScore(row);
    if (score > bestScore) {
      bestScore = score;
      bestUrl = url;
    }
  }

  return bestUrl;
}

String? _preferredImageUrlFromValidation(Map<String, dynamic> json) {
  final imageValidation = _map(json['imageValidation']);
  final creativeHealth = _map(json['creativeHealth']);
  final analyzedPreferred =
      _bestAnalyzedImageUrl(imageValidation?['analyzedImages']);
  if (analyzedPreferred != null) {
    return analyzedPreferred;
  }

  final selected = _string(imageValidation?['selectedImageUrl']) ??
      _string(creativeHealth?['selectedImageUrl']);
  if (selected != null && selected.trim().isNotEmpty) {
    return selected.trim();
  }
  return null;
}

List<ItemImage> _parseImages(List<dynamic> imagesRaw) {
  return imagesRaw.map((e) {
    if (e is String) {
      // Handle legacy format where images are stored as plain URL strings.
      return ItemImage.fromJson({'url': e});
    } else if (e is Map) {
      return ItemImage.fromJson(Map<String, dynamic>.from(e));
    } else {
      return ItemImage.fromJson(<String, dynamic>{});
    }
  }).toList();
}

List<ItemImage> _prioritizePreferredImage(
  List<ItemImage> images,
  String? preferredImageUrl,
) {
  if (images.isEmpty ||
      preferredImageUrl == null ||
      preferredImageUrl.isEmpty) {
    return images;
  }

  final preferred = preferredImageUrl.trim();
  final idx = images.indexWhere((img) => img.url.trim() == preferred);
  if (idx <= 0) return images;

  final reordered = List<ItemImage>.from(images);
  final preferredImage = reordered.removeAt(idx);
  reordered.insert(0, preferredImage);
  return reordered;
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
    final preferredImageUrl = _preferredImageUrlFromValidation(json);
    final parsedImages = _parseImages(imagesRaw.cast<dynamic>());
    final prioritizedImages =
        _prioritizePreferredImage(parsedImages, preferredImageUrl);

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
      title: _cleanTitle(json['title']) ?? '',
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
      images: prioritizedImages,
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
