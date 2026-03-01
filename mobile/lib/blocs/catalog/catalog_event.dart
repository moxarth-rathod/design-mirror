/// DesignMirror AI — Catalog BLoC Events

import 'package:equatable/equatable.dart';

abstract class CatalogEvent extends Equatable {
  const CatalogEvent();

  @override
  List<Object?> get props => [];
}

/// Load the initial catalog page.
class CatalogLoadRequested extends CatalogEvent {}

/// Load the next page (infinite scroll).
class CatalogNextPageRequested extends CatalogEvent {}

/// User selected a category filter.
class CatalogCategoryChanged extends CatalogEvent {
  final String? category;

  const CatalogCategoryChanged({this.category});

  @override
  List<Object?> get props => [category];
}

/// User typed a search query.
class CatalogSearchChanged extends CatalogEvent {
  final String query;

  const CatalogSearchChanged({required this.query});

  @override
  List<Object?> get props => [query];
}

/// Load catalog filtered to a specific room's dimensions.
class CatalogFilterByRoomRequested extends CatalogEvent {
  final String roomId;
  final String roomName;
  final double widthM;
  final double lengthM;
  final double? heightM;

  const CatalogFilterByRoomRequested({
    required this.roomId,
    required this.roomName,
    required this.widthM,
    required this.lengthM,
    this.heightM,
  });

  @override
  List<Object?> get props => [roomId, widthM, lengthM];
}

/// User changed price range filter.
class CatalogPriceFilterChanged extends CatalogEvent {
  final double? minPriceInr;
  final double? maxPriceInr;

  const CatalogPriceFilterChanged({this.minPriceInr, this.maxPriceInr});

  @override
  List<Object?> get props => [minPriceInr, maxPriceInr];
}

/// Clear room filter.
class CatalogRoomFilterCleared extends CatalogEvent {}
