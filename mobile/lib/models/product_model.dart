/// DesignMirror AI — Product Model (Dart)
///
/// Mirrors the backend's ProductResponse schema.

import 'package:design_mirror/config/units.dart';

class BoundingBox3D {
  final double widthM;
  final double depthM;
  final double heightM;

  const BoundingBox3D({
    required this.widthM,
    required this.depthM,
    required this.heightM,
  });

  double get volumeM3 => widthM * depthM * heightM;
  double get footprintM2 => widthM * depthM;

  /// Compact display using global unit preference: W × D × H
  String get displayString =>
      DimensionFormatter.formatCompact(widthM, depthM, heightM);

  factory BoundingBox3D.fromJson(Map<String, dynamic> json) {
    return BoundingBox3D(
      widthM: (json['width_m'] as num).toDouble(),
      depthM: (json['depth_m'] as num).toDouble(),
      heightM: (json['height_m'] as num).toDouble(),
    );
  }
}

class ProductModel {
  final String id;
  final String name;
  final String category;
  final String description;
  final BoundingBox3D boundingBox;
  final String color;
  final double priceUsd;
  final String? imageUrl;
  final String? modelFile;
  final List<String> tags;

  const ProductModel({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.boundingBox,
    required this.color,
    required this.priceUsd,
    this.imageUrl,
    this.modelFile,
    required this.tags,
  });

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    return ProductModel(
      id: json['id'] as String,
      name: json['name'] as String,
      category: json['category'] as String,
      description: json['description'] as String? ?? '',
      boundingBox:
          BoundingBox3D.fromJson(json['bounding_box'] as Map<String, dynamic>),
      color: json['color'] as String? ?? '',
      priceUsd: (json['price_usd'] as num).toDouble(),
      imageUrl: json['image_url'] as String?,
      modelFile: json['model_file'] as String?,
      tags: (json['tags'] as List<dynamic>?)
              ?.map((t) => t as String)
              .toList() ??
          [],
    );
  }

  static const double _usdToInr = 83.5;

  double get priceInr => priceUsd * _usdToInr;

  String get priceFormatted {
    final inr = priceInr.round();
    final str = inr.toString();
    final buf = StringBuffer();
    final len = str.length;
    // Indian grouping: last 3 digits, then groups of 2
    for (int i = 0; i < len; i++) {
      buf.write(str[i]);
      final remaining = len - i - 1;
      if (remaining > 0 && remaining % 2 == 1 && remaining >= 3) {
        buf.write(',');
      }
    }
    return '₹$buf';
  }
}

class CatalogPage {
  final List<ProductModel> items;
  final int total;
  final int page;
  final int pageSize;
  final bool hasNext;

  const CatalogPage({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.hasNext,
  });

  factory CatalogPage.fromJson(Map<String, dynamic> json) {
    return CatalogPage(
      items: (json['items'] as List<dynamic>)
          .map((item) => ProductModel.fromJson(item as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int,
      page: json['page'] as int,
      pageSize: json['page_size'] as int,
      hasNext: json['has_next'] as bool,
    );
  }
}
