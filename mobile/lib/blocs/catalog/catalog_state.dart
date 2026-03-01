/// DesignMirror AI — Catalog BLoC States

import 'package:equatable/equatable.dart';

import '../../models/product_model.dart';

abstract class CatalogState extends Equatable {
  const CatalogState();

  @override
  List<Object?> get props => [];
}

class CatalogInitial extends CatalogState {}

class CatalogLoading extends CatalogState {}

/// Catalog loaded successfully. Supports infinite scroll and room filtering.
class CatalogLoaded extends CatalogState {
  final List<ProductModel> products;
  final int total;
  final bool hasNext;
  final int currentPage;
  final String? activeCategory;
  final String? searchQuery;
  final bool isLoadingMore;

  /// Room filter context (when browsing furniture for a specific room).
  final String? filterRoomId;
  final String? filterRoomName;
  final double? filterWidthM;
  final double? filterLengthM;
  final double? filterHeightM;

  /// Price filter (INR values — converted to USD when calling API).
  final double? minPriceInr;
  final double? maxPriceInr;

  const CatalogLoaded({
    required this.products,
    required this.total,
    required this.hasNext,
    required this.currentPage,
    this.activeCategory,
    this.searchQuery,
    this.isLoadingMore = false,
    this.filterRoomId,
    this.filterRoomName,
    this.filterWidthM,
    this.filterLengthM,
    this.filterHeightM,
    this.minPriceInr,
    this.maxPriceInr,
  });

  bool get hasRoomFilter => filterRoomId != null;

  bool get hasPriceFilter => minPriceInr != null || maxPriceInr != null;

  @override
  List<Object?> get props => [
        products.length,
        total,
        hasNext,
        currentPage,
        activeCategory,
        searchQuery,
        isLoadingMore,
        filterRoomId,
        minPriceInr,
        maxPriceInr,
      ];

  CatalogLoaded copyWith({
    List<ProductModel>? products,
    int? total,
    bool? hasNext,
    int? currentPage,
    String? activeCategory,
    String? searchQuery,
    bool? isLoadingMore,
    String? filterRoomId,
    String? filterRoomName,
    double? filterWidthM,
    double? filterLengthM,
    double? filterHeightM,
    double? minPriceInr,
    double? maxPriceInr,
  }) {
    return CatalogLoaded(
      products: products ?? this.products,
      total: total ?? this.total,
      hasNext: hasNext ?? this.hasNext,
      currentPage: currentPage ?? this.currentPage,
      activeCategory: activeCategory,
      searchQuery: searchQuery ?? this.searchQuery,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      filterRoomId: filterRoomId ?? this.filterRoomId,
      filterRoomName: filterRoomName ?? this.filterRoomName,
      filterWidthM: filterWidthM ?? this.filterWidthM,
      filterLengthM: filterLengthM ?? this.filterLengthM,
      filterHeightM: filterHeightM ?? this.filterHeightM,
      minPriceInr: minPriceInr ?? this.minPriceInr,
      maxPriceInr: maxPriceInr ?? this.maxPriceInr,
    );
  }
}

class CatalogError extends CatalogState {
  final String message;

  const CatalogError({required this.message});

  @override
  List<Object?> get props => [message];
}
