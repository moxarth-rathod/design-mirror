/// DesignMirror AI — Wishlist Repository

import '../services/api_service.dart';

class WishlistRepository {
  final ApiService _api;

  WishlistRepository({required ApiService apiService}) : _api = apiService;

  Future<List<Map<String, dynamic>>> getWishlist() async {
    final response = await _api.get('/wishlist');
    return (response.data as List<dynamic>)
        .map((e) => e as Map<String, dynamic>)
        .toList();
  }

  Future<List<String>> getWishlistIds() async {
    final response = await _api.get('/wishlist/ids');
    return (response.data as List<dynamic>).map((e) => e as String).toList();
  }

  Future<void> addToWishlist(String productId) async {
    await _api.post('/wishlist', data: {'product_id': productId});
  }

  Future<void> removeFromWishlist(String productId) async {
    await _api.delete('/wishlist/$productId');
  }
}
