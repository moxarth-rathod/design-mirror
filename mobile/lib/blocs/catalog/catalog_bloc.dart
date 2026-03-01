/// DesignMirror AI — Catalog BLoC
///
/// Manages catalog browsing state with support for:
///   • Paginated loading (infinite scroll)
///   • Category filtering
///   • Text search

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';

import '../../repositories/catalog_repository.dart';
import 'catalog_event.dart';
import 'catalog_state.dart';

class CatalogBloc extends Bloc<CatalogEvent, CatalogState> {
  final CatalogRepository _catalogRepository;
  final Logger _logger = Logger();

  CatalogBloc({required CatalogRepository catalogRepository})
      : _catalogRepository = catalogRepository,
        super(CatalogInitial()) {
    on<CatalogLoadRequested>(_onLoadRequested);
    on<CatalogNextPageRequested>(_onNextPageRequested);
    on<CatalogCategoryChanged>(_onCategoryChanged);
    on<CatalogSearchChanged>(_onSearchChanged);
    on<CatalogPriceFilterChanged>(_onPriceFilterChanged);
    on<CatalogFilterByRoomRequested>(_onFilterByRoom);
    on<CatalogRoomFilterCleared>(_onRoomFilterCleared);
  }

  static const double _inrToUsd = 1 / 83.5;

  /// Load the first page of the catalog.
  Future<void> _onLoadRequested(
    CatalogLoadRequested event,
    Emitter<CatalogState> emit,
  ) async {
    emit(CatalogLoading());
    try {
      final page = await _catalogRepository.getCatalog();
      emit(CatalogLoaded(
        products: page.items,
        total: page.total,
        hasNext: page.hasNext,
        currentPage: 1,
      ));
      _logger.i('Catalog loaded: ${page.items.length}/${page.total} products');
    } catch (e) {
      emit(CatalogError(message: e.toString()));
    }
  }

  /// Load the next page (infinite scroll).
  Future<void> _onNextPageRequested(
    CatalogNextPageRequested event,
    Emitter<CatalogState> emit,
  ) async {
    if (state is! CatalogLoaded) return;
    final current = state as CatalogLoaded;
    if (!current.hasNext || current.isLoadingMore) return;

    emit(current.copyWith(isLoadingMore: true));

    try {
      final nextPage = await _catalogRepository.getCatalog(
        category: current.activeCategory,
        search: current.searchQuery,
        minPrice: current.minPriceInr != null
            ? current.minPriceInr! * _inrToUsd
            : null,
        maxPrice: current.maxPriceInr != null
            ? current.maxPriceInr! * _inrToUsd
            : null,
        maxWidthM: current.filterWidthM,
        maxDepthM: current.filterLengthM,
        maxHeightM: current.filterHeightM,
        page: current.currentPage + 1,
      );

      emit(current.copyWith(
        products: [...current.products, ...nextPage.items],
        total: nextPage.total,
        hasNext: nextPage.hasNext,
        currentPage: current.currentPage + 1,
        isLoadingMore: false,
      ));
    } catch (e) {
      emit(current.copyWith(isLoadingMore: false));
      _logger.e('Failed to load next page: $e');
    }
  }

  /// Filter by category (null = show all).
  Future<void> _onCategoryChanged(
    CatalogCategoryChanged event,
    Emitter<CatalogState> emit,
  ) async {
    final prev = state is CatalogLoaded ? state as CatalogLoaded : null;
    emit(CatalogLoading());
    try {
      final page = await _catalogRepository.getCatalog(
        category: event.category,
        minPrice: prev?.minPriceInr != null
            ? prev!.minPriceInr! * _inrToUsd
            : null,
        maxPrice: prev?.maxPriceInr != null
            ? prev!.maxPriceInr! * _inrToUsd
            : null,
        maxWidthM: prev?.filterWidthM,
        maxDepthM: prev?.filterLengthM,
        maxHeightM: prev?.filterHeightM,
      );
      emit(CatalogLoaded(
        products: page.items,
        total: page.total,
        hasNext: page.hasNext,
        currentPage: 1,
        activeCategory: event.category,
        filterRoomId: prev?.filterRoomId,
        filterRoomName: prev?.filterRoomName,
        filterWidthM: prev?.filterWidthM,
        filterLengthM: prev?.filterLengthM,
        filterHeightM: prev?.filterHeightM,
        minPriceInr: prev?.minPriceInr,
        maxPriceInr: prev?.maxPriceInr,
      ));
    } catch (e) {
      emit(CatalogError(message: e.toString()));
    }
  }

  /// Search products by text.
  Future<void> _onSearchChanged(
    CatalogSearchChanged event,
    Emitter<CatalogState> emit,
  ) async {
    final prev = state is CatalogLoaded ? state as CatalogLoaded : null;
    emit(CatalogLoading());
    try {
      final page = await _catalogRepository.getCatalog(
        search: event.query.isEmpty ? null : event.query,
        minPrice: prev?.minPriceInr != null
            ? prev!.minPriceInr! * _inrToUsd
            : null,
        maxPrice: prev?.maxPriceInr != null
            ? prev!.maxPriceInr! * _inrToUsd
            : null,
        maxWidthM: prev?.filterWidthM,
        maxDepthM: prev?.filterLengthM,
        maxHeightM: prev?.filterHeightM,
      );
      emit(CatalogLoaded(
        products: page.items,
        total: page.total,
        hasNext: page.hasNext,
        currentPage: 1,
        searchQuery: event.query.isEmpty ? null : event.query,
        filterRoomId: prev?.filterRoomId,
        filterRoomName: prev?.filterRoomName,
        filterWidthM: prev?.filterWidthM,
        filterLengthM: prev?.filterLengthM,
        filterHeightM: prev?.filterHeightM,
        minPriceInr: prev?.minPriceInr,
        maxPriceInr: prev?.maxPriceInr,
      ));
    } catch (e) {
      emit(CatalogError(message: e.toString()));
    }
  }

  /// Apply price range filter.
  Future<void> _onPriceFilterChanged(
    CatalogPriceFilterChanged event,
    Emitter<CatalogState> emit,
  ) async {
    final prev = state is CatalogLoaded ? state as CatalogLoaded : null;
    emit(CatalogLoading());
    try {
      final page = await _catalogRepository.getCatalog(
        category: prev?.activeCategory,
        search: prev?.searchQuery,
        minPrice: event.minPriceInr != null
            ? event.minPriceInr! * _inrToUsd
            : null,
        maxPrice: event.maxPriceInr != null
            ? event.maxPriceInr! * _inrToUsd
            : null,
        maxWidthM: prev?.filterWidthM,
        maxDepthM: prev?.filterLengthM,
        maxHeightM: prev?.filterHeightM,
      );
      emit(CatalogLoaded(
        products: page.items,
        total: page.total,
        hasNext: page.hasNext,
        currentPage: 1,
        activeCategory: prev?.activeCategory,
        searchQuery: prev?.searchQuery,
        filterRoomId: prev?.filterRoomId,
        filterRoomName: prev?.filterRoomName,
        filterWidthM: prev?.filterWidthM,
        filterLengthM: prev?.filterLengthM,
        filterHeightM: prev?.filterHeightM,
        minPriceInr: event.minPriceInr,
        maxPriceInr: event.maxPriceInr,
      ));
    } catch (e) {
      emit(CatalogError(message: e.toString()));
    }
  }

  /// Load catalog filtered to fit a specific room.
  Future<void> _onFilterByRoom(
    CatalogFilterByRoomRequested event,
    Emitter<CatalogState> emit,
  ) async {
    emit(CatalogLoading());
    try {
      final page = await _catalogRepository.getCatalog(
        maxWidthM: event.widthM,
        maxDepthM: event.lengthM,
        maxHeightM: event.heightM,
      );
      emit(CatalogLoaded(
        products: page.items,
        total: page.total,
        hasNext: page.hasNext,
        currentPage: 1,
        filterRoomId: event.roomId,
        filterRoomName: event.roomName,
        filterWidthM: event.widthM,
        filterLengthM: event.lengthM,
        filterHeightM: event.heightM,
      ));
      _logger.i(
        'Catalog filtered for room "${event.roomName}" '
        '(${event.widthM}×${event.lengthM}m): ${page.items.length} products',
      );
    } catch (e) {
      emit(CatalogError(message: e.toString()));
    }
  }

  /// Clear room filter and reload all products.
  Future<void> _onRoomFilterCleared(
    CatalogRoomFilterCleared event,
    Emitter<CatalogState> emit,
  ) async {
    emit(CatalogLoading());
    try {
      final page = await _catalogRepository.getCatalog();
      emit(CatalogLoaded(
        products: page.items,
        total: page.total,
        hasNext: page.hasNext,
        currentPage: 1,
      ));
    } catch (e) {
      emit(CatalogError(message: e.toString()));
    }
  }
}
