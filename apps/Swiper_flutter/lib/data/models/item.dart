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

  String? get firstImageUrl => images.isNotEmpty ? images.first.url : null;

  factory Item.fromJson(Map<String, dynamic> json) {
    final imagesRaw = json['images'] as List? ?? [];
    return Item(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      priceAmount: (json['priceAmount'] as num?)?.toDouble() ?? 0,
      priceCurrency: json['priceCurrency'] as String? ?? 'SEK',
      sourceId: json['sourceId'] as String?,
      sourceUrl: json['sourceUrl'] as String?,
      outboundUrl: json['outboundUrl'] as String?,
      brand: json['brand'] as String?,
      descriptionShort: json['descriptionShort'] as String?,
      dimensionsCm: json['dimensionsCm'] != null ? Map<String, num>.from((json['dimensionsCm'] as Map).map((k, v) => MapEntry(k.toString(), (v as num)))) : null,
      sizeClass: json['sizeClass'] as String?,
      material: json['material'] as String?,
      colorFamily: json['colorFamily'] as String?,
      styleTags: List<String>.from(json['styleTags'] as List? ?? []),
      newUsed: json['newUsed'] as String? ?? 'new',
      deliveryComplexity: json['deliveryComplexity'] as String?,
      smallSpaceFriendly: json['smallSpaceFriendly'] as bool? ?? false,
      modular: json['modular'] as bool? ?? false,
      ecoTags: List<String>.from(json['ecoTags'] as List? ?? []),
      images: imagesRaw.map((e) => ItemImage.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      lastUpdatedAt: json['lastUpdatedAt'] != null ? DateTime.tryParse(json['lastUpdatedAt'] as String) : null,
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
      if (lastUpdatedAt != null) 'lastUpdatedAt': lastUpdatedAt!.toIso8601String(),
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
      url: json['url'] as String? ?? '',
      width: json['width'] as int?,
      height: json['height'] as int?,
      alt: json['alt'] as String?,
      type: json['type'] as String?,
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
