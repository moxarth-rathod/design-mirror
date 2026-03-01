import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/theme.dart';
import '../../repositories/room_repository.dart';

final _catIcons = <String, IconData>{
  'bed': Icons.bed_outlined,
  'sofa': Icons.weekend_outlined,
  'table': Icons.table_restaurant_outlined,
  'chair': Icons.chair_outlined,
  'desk': Icons.desk_outlined,
  'lighting': Icons.light_outlined,
  'storage': Icons.inventory_2_outlined,
  'rug': Icons.rectangle_outlined,
  'nightstand': Icons.nightlight_outlined,
  'dresser': Icons.inventory_2_outlined,
  'wardrobe': Icons.door_sliding_outlined,
  'mirror': Icons.border_all_outlined,
  'decor': Icons.palette_outlined,
  'plant': Icons.local_florist_outlined,
};

class RecommendationsScreen extends StatefulWidget {
  const RecommendationsScreen({super.key});

  @override
  State<RecommendationsScreen> createState() => _RecommendationsScreenState();
}

class _RecommendationsScreenState extends State<RecommendationsScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  late String _roomId;
  late String _roomName;
  String? _roomType;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _readParamsAndLoad());
  }

  void _readParamsAndLoad() {
    final uri = GoRouterState.of(context).uri;
    _roomId = uri.queryParameters['roomId'] ?? uri.queryParameters['room_id'] ?? '';
    _roomName = Uri.decodeComponent(uri.queryParameters['roomName'] ?? uri.queryParameters['room_name'] ?? 'Room');
    _roomType = uri.queryParameters['roomType'] ?? uri.queryParameters['room_type'];

    if (_roomId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Room ID is required';
      });
      return;
    }
    _loadRecommendations();
  }

  Future<void> _loadRecommendations() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = GetIt.instance<RoomRepository>();
      final data = await repo.getRecommendations(_roomId);
      if (mounted) {
        setState(() {
          _data = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  String _formatRoomType(String? type) {
    if (type == null || type.isEmpty) return '';
    return type
        .split('_')
        .map((s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}')
        .join(' ');
  }

  String _formatPriceInr(num priceUsd) {
    final inr = (priceUsd * 83.5).round();
    if (inr >= 1000) {
      return '₹${inr.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';
    }
    return '₹$inr';
  }

  String _formatDimensions(Map<String, dynamic>? bb) {
    if (bb == null) return '';
    final w = (bb['width_m'] as num?)?.toDouble();
    final d = (bb['depth_m'] as num?)?.toDouble();
    final h = (bb['height_m'] as num?)?.toDouble();
    if (w == null || d == null || h == null) return '';
    return '${w.toStringAsFixed(1)}×${d.toStringAsFixed(1)}×${h.toStringAsFixed(1)}m';
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recommendations'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(36),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _roomName,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.secondaryTextOf(context),
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_roomType != null && _roomType!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withAlpha(40),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _formatRoomType(_roomType),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.accent,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppTheme.error),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadRecommendations,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final roomTypeFromData = _data?['room_type'] as String?;
    final effectiveRoomType = _roomType ?? roomTypeFromData;

    if (effectiveRoomType == null || effectiveRoomType.isEmpty) {
      return _buildNoRoomTypeCard();
    }

    final groups = _data?['groups'] as List<dynamic>? ?? [];
    if (groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 64, color: AppTheme.mutedOf(context).withAlpha(100)),
            const SizedBox(height: 16),
            Text(
              'No recommendations yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Check back later for curated picks',
              style: TextStyle(color: AppTheme.secondaryTextOf(context)),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final group = groups[index] as Map<String, dynamic>;
              return _buildCategorySection(group, effectiveRoomType);
            },
          ),
        ),
        _buildPlanLayoutButton(),
      ],
    );
  }

  Widget _buildNoRoomTypeCard() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.primary.withAlpha(25),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.primary.withAlpha(60)),
            ),
            child: Column(
              children: [
                const Icon(Icons.info_outline, size: 40, color: AppTheme.primary),
                const SizedBox(height: 16),
                Text(
                  'Set a room type to get personalized recommendations',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => context.pop(),
                    child: const Text('Go Back'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySection(Map<String, dynamic> group, String roomType) {
    final category = group['category'] as String? ?? '';
    final products = group['products'] as List<dynamic>? ?? [];
    if (products.isEmpty) return const SizedBox.shrink();

    final roomTypeLabel = _formatRoomType(roomType);
    final categoryLabel = _capitalize(category);
    final sectionTitle = '$categoryLabel for your $roomTypeLabel';

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _catIcons[category] ?? Icons.inventory_2_outlined,
                size: 22,
                color: AppTheme.accent,
              ),
              const SizedBox(width: 8),
              Text(
                sectionTitle,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: products.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final product = products[index] as Map<String, dynamic>;
                return _buildProductCard(product);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    final name = product['name'] as String? ?? 'Product';
    final category = product['category'] as String? ?? '';
    final priceUsd = (product['price_usd'] as num?) ?? 0;
    final imageUrl = product['image_url'] as String?;
    final bb = product['bounding_box'] as Map<String, dynamic>?;
    final dimsStr = _formatDimensions(bb);

    return SizedBox(
      width: 150,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(
            '/catalog?room_id=$_roomId&room_name=${Uri.encodeComponent(_roomName)}',
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  color: AppTheme.surfaceDimOf(context),
                  child: imageUrl != null && imageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Center(
                            child: Icon(
                              _catIcons[category] ?? Icons.inventory_2_outlined,
                              size: 36,
                              color: AppTheme.mutedOf(context).withAlpha(120),
                            ),
                          ),
                          errorWidget: (_, __, ___) => Center(
                            child: Icon(
                              _catIcons[category] ?? Icons.inventory_2_outlined,
                              size: 36,
                              color: AppTheme.mutedOf(context),
                            ),
                          ),
                        )
                      : Center(
                          child: Icon(
                            _catIcons[category] ?? Icons.inventory_2_outlined,
                            size: 36,
                            color: AppTheme.mutedOf(context),
                          ),
                        ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (dimsStr.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        dimsStr,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.secondaryTextOf(context),
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      _formatPriceInr(priceUsd),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppTheme.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlanLayoutButton() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(20),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => context.push(
              '/layout-planner?room_id=$_roomId',
            ),
            icon: const Icon(Icons.grid_view_rounded, size: 20),
            label: const Text('Plan Full Layout'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.success,
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
