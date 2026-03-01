/// DesignMirror AI — Catalog Repository
///
/// Handles communication with the catalog API endpoints.

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';

import '../models/product_model.dart';
import '../services/api_service.dart';

class CatalogRepository {
  final ApiService _api;
  final Logger _logger = Logger();

  CatalogRepository({required ApiService apiService}) : _api = apiService;

  /// Fetch a paginated, filtered page of products.
  Future<CatalogPage> getCatalog({
    String? category,
    String? search,
    double? minPrice,
    double? maxPrice,
    double? maxWidthM,
    double? maxDepthM,
    double? maxHeightM,
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'page': page,
        'page_size': pageSize,
      };
      if (category != null) queryParams['category'] = category;
      if (search != null) queryParams['search'] = search;
      if (minPrice != null) queryParams['min_price'] = minPrice;
      if (maxPrice != null) queryParams['max_price'] = maxPrice;
      if (maxWidthM != null) queryParams['max_width_m'] = maxWidthM;
      if (maxDepthM != null) queryParams['max_depth_m'] = maxDepthM;
      if (maxHeightM != null) queryParams['max_height_m'] = maxHeightM;

      final response = await _api.get('/catalog', queryParams: queryParams);
      return CatalogPage.fromJson(response.data);
    } on DioException catch (e) {
      throw _extractError(e);
    }
  }

  /// Run a fit-check for a product in a room.
  /// If [x], [z], [rotationY] are all zero (default), the backend's AI
  /// placement engine automatically picks the optimal position.
  Future<Map<String, dynamic>> checkFit({
    required String roomId,
    required String productId,
    double? x,
    double? z,
    double? rotationY,
  }) async {
    try {
      final data = <String, dynamic>{
        'room_id': roomId,
        'product_id': productId,
      };
      if (x != null || z != null || rotationY != null) {
        data['position'] = {
          'x': x ?? 0,
          'z': z ?? 0,
          'rotation_y': rotationY ?? 0,
        };
      }
      final response = await _api.post('/fitcheck', data: data);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _extractError(e);
    }
  }

  /// Fetch a single product by ID.
  Future<ProductModel> getProduct(String productId) async {
    try {
      final response = await _api.get('/catalog/$productId');
      return ProductModel.fromJson(response.data);
    } on DioException catch (e) {
      throw _extractError(e);
    }
  }

  /// Fetch all available categories.
  Future<List<String>> getCategories() async {
    try {
      final response = await _api.get('/catalog/categories');
      return (response.data as List<dynamic>)
          .map((c) => c as String)
          .toList();
    } on DioException catch (e) {
      throw _extractError(e);
    }
  }

  String _extractError(DioException e) {
    if (e.response?.data != null && e.response!.data is Map) {
      final detail = e.response!.data['detail'];
      if (detail != null) return detail.toString();
    }
    return 'Failed to load catalog. Please try again.';
  }
}
