/// DesignMirror AI — Wishlist Screen

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../repositories/wishlist_repository.dart';

class WishlistScreen extends StatefulWidget {
  const WishlistScreen({super.key});

  @override
  State<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends State<WishlistScreen> {
  final _repo = GetIt.instance<WishlistRepository>();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _items = await _repo.getWishlist();
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _remove(String productId, int index) async {
    final removed = _items.removeAt(index);
    setState(() {});
    try {
      await _repo.removeFromWishlist(productId);
    } catch (_) {
      _items.insert(index, removed);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Wishlist')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : _items.isEmpty
                  ? _buildEmpty()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: _buildItem,
                      ),
                    ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.favorite_border_rounded,
              size: 64, color: AppTheme.mutedOf(context)),
          const SizedBox(height: 16),
          Text('No saved items yet',
              style: TextStyle(
                  fontSize: 18, color: AppTheme.secondaryTextOf(context))),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => context.push(AppRoutes.catalog),
            child: const Text('Browse Furniture'),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context, int index) {
    final item = _items[index];
    final priceUsd = (item['product_price_usd'] as num?) ?? 0;
    final priceInr = (priceUsd * 83.5).round();
    final imageUrl = item['product_image_url'] as String?;

    return Dismissible(
      key: ValueKey(item['id']),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppTheme.error.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(Icons.delete_outline, color: AppTheme.error),
      ),
      onDismissed: (_) => _remove(item['product_id'] as String, index),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 56,
              height: 56,
              child: imageUrl != null && imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                          color: AppTheme.surfaceDimOf(context)),
                      errorWidget: (_, __, ___) =>
                          _iconPlaceholder(item['product_category'] as String?),
                    )
                  : _iconPlaceholder(item['product_category'] as String?),
            ),
          ),
          title: Text(
            item['product_name'] as String? ?? '',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          subtitle: Text(
            '${_capitalize(item['product_category'] as String? ?? '')}  •  ₹${_indianComma(priceInr)}',
            style: TextStyle(
                fontSize: 13, color: AppTheme.secondaryTextOf(context)),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.favorite_rounded, color: AppTheme.accent),
            onPressed: () => _remove(item['product_id'] as String, index),
          ),
          onTap: () => context.push(AppRoutes.catalog),
        ),
      ),
    );
  }

  Widget _iconPlaceholder(String? category) {
    return Container(
      color: AppTheme.surfaceDimOf(context),
      child: Icon(
        _categoryIcon(category),
        color: AppTheme.mutedOf(context),
        size: 28,
      ),
    );
  }

  IconData _categoryIcon(String? cat) {
    switch (cat) {
      case 'bed':
        return Icons.bed_outlined;
      case 'sofa':
        return Icons.weekend_outlined;
      case 'table':
        return Icons.table_restaurant_outlined;
      case 'lamp':
        return Icons.light_outlined;
      default:
        return Icons.chair_outlined;
    }
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  String _indianComma(int n) {
    if (n < 0) return '-${_indianComma(-n)}';
    final s = n.toString();
    if (s.length <= 3) return s;
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    return '${parts.join(',')},${last3}';
  }
}
