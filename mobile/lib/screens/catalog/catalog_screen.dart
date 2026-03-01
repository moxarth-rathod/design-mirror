/// DesignMirror AI — Catalog Screen
///
/// Browsable furniture catalog with search, category filters,
/// and infinite scroll pagination.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

import '../../blocs/catalog/catalog_bloc.dart';
import '../../blocs/catalog/catalog_event.dart';
import '../../blocs/catalog/catalog_state.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/product_model.dart';
import '../../models/room_model.dart';
import '../../repositories/catalog_repository.dart';
import '../../repositories/room_repository.dart';
import '../../repositories/wishlist_repository.dart';
import '../../config/units.dart';
import '../../services/pdf_export_service.dart';
import '../../widgets/room_dimension_view.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _minPriceCtrl = TextEditingController();
  final _maxPriceCtrl = TextEditingController();
  final _wishlistRepo = GetIt.instance<WishlistRepository>();
  final Set<String> _wishlistIds = {};
  bool _priceFilterActive = false;
  final GlobalKey _diagramKey = GlobalKey();

  void _onUnitChanged() => setState(() {});

  @override
  void initState() {
    super.initState();

    DimensionFormatter.currentUnit.addListener(_onUnitChanged);
    _loadWishlistIds();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final uri = GoRouterState.of(context).uri;
      final roomId = uri.queryParameters['room_id'];
      final roomName = uri.queryParameters['room_name'];
      final width = double.tryParse(uri.queryParameters['width'] ?? '');
      final length = double.tryParse(uri.queryParameters['length'] ?? '');
      final height = double.tryParse(uri.queryParameters['height'] ?? '');

      if (roomId != null && width != null && width > 0 && length != null && length > 0) {
        context.read<CatalogBloc>().add(CatalogFilterByRoomRequested(
              roomId: roomId,
              roomName: roomName ?? 'Room',
              widthM: width,
              lengthM: length,
              heightM: (height != null && height > 0) ? height : null,
            ));
      } else {
        context.read<CatalogBloc>().add(CatalogLoadRequested());
      }
    });

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        context.read<CatalogBloc>().add(CatalogNextPageRequested());
      }
    });
  }

  Future<void> _loadWishlistIds() async {
    try {
      final ids = await _wishlistRepo.getWishlistIds();
      if (mounted) setState(() => _wishlistIds..clear()..addAll(ids));
    } catch (_) {}
  }

  Future<void> _toggleWishlist(String productId) async {
    final wasIn = _wishlistIds.contains(productId);
    setState(() {
      if (wasIn) {
        _wishlistIds.remove(productId);
      } else {
        _wishlistIds.add(productId);
      }
    });
    try {
      if (wasIn) {
        await _wishlistRepo.removeFromWishlist(productId);
      } else {
        await _wishlistRepo.addToWishlist(productId);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          if (wasIn) {
            _wishlistIds.add(productId);
          } else {
            _wishlistIds.remove(productId);
          }
        });
      }
    }
  }

  @override
  void dispose() {
    DimensionFormatter.currentUnit.removeListener(_onUnitChanged);
    _searchController.dispose();
    _scrollController.dispose();
    _minPriceCtrl.dispose();
    _maxPriceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Furniture Catalog'),
        actions: [
          _buildUnitToggle(),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // ── Room Filter Banner ────────────
          BlocBuilder<CatalogBloc, CatalogState>(
            builder: (context, state) {
              if (state is CatalogLoaded && state.hasRoomFilter) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: AppTheme.primary.withAlpha(15),
                  child: Row(
                    children: [
                      Icon(Icons.filter_alt, size: 18, color: AppTheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Showing furniture that fits "${state.filterRoomName}" '
                          '(${DimensionFormatter.format(state.filterWidthM ?? 0)} × '
                          '${DimensionFormatter.format(state.filterLengthM ?? 0)})',
                          style: TextStyle(fontSize: 12, color: AppTheme.primary),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => context.read<CatalogBloc>().add(CatalogRoomFilterCleared()),
                        child: Icon(Icons.close, size: 18, color: AppTheme.secondaryTextOf(context)),
                      ),
                    ],
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),

          // ── Search Bar ────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search furniture...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          context
                              .read<CatalogBloc>()
                              .add(const CatalogSearchChanged(query: ''));
                        },
                      )
                    : null,
              ),
              onChanged: (value) {
                setState(() {});
                context
                    .read<CatalogBloc>()
                    .add(CatalogSearchChanged(query: value));
              },
            ),
          ),

          // ── Filter Chips (Type + Price) ───
          _buildFilterChips(),
          const SizedBox(height: 4),

          // ── Product Grid ──────────────────
          Expanded(
            child: BlocBuilder<CatalogBloc, CatalogState>(
              builder: (context, state) {
                if (state is CatalogLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (state is CatalogError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline,
                            size: 48, color: AppTheme.error),
                        const SizedBox(height: 12),
                        Text(state.message),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: () => context
                              .read<CatalogBloc>()
                              .add(CatalogLoadRequested()),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                if (state is CatalogLoaded) {
                  if (state.products.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inventory_2_outlined,
                              size: 64,
                              color: AppTheme.mutedOf(context).withValues(alpha: 0.5)),
                          const SizedBox(height: 16),
                          const Text('No products found'),
                          const SizedBox(height: 8),
                          Text(
                            'Try a different search or category',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    );
                  }

                  return GridView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.58,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount:
                        state.products.length + (state.isLoadingMore ? 2 : 0),
                    itemBuilder: (context, index) {
                      if (index >= state.products.length) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      }
                      return _buildProductCard(state.products[index]);
                    },
                  );
                }

                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return BlocBuilder<CatalogBloc, CatalogState>(
      builder: (context, state) {
        final activeCategory =
            state is CatalogLoaded ? state.activeCategory : null;
        final hasTypeFilter = activeCategory != null;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              // ── Type Filter Chip ──
              FilterChip(
                avatar: Icon(
                  Icons.category_rounded,
                  size: 16,
                  color: hasTypeFilter
                      ? Colors.white
                      : AppTheme.secondaryTextOf(context),
                ),
                label: Text(hasTypeFilter
                    ? _capitalize(activeCategory)
                    : 'Type'),
                selected: hasTypeFilter,
                onSelected: (_) => _showTypeFilterSheet(),
                selectedColor: AppTheme.accent,
                checkmarkColor: Colors.white,
                labelStyle: hasTypeFilter
                    ? const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)
                    : null,
                deleteIcon: hasTypeFilter
                    ? const Icon(Icons.close, size: 16, color: Colors.white)
                    : null,
                onDeleted: hasTypeFilter
                    ? () => context
                        .read<CatalogBloc>()
                        .add(const CatalogCategoryChanged(category: null))
                    : null,
              ),
              const SizedBox(width: 10),
              // ── Price Filter Chip ──
              FilterChip(
                avatar: Icon(
                  Icons.currency_rupee_rounded,
                  size: 16,
                  color: _priceFilterActive
                      ? Colors.white
                      : AppTheme.secondaryTextOf(context),
                ),
                label: Text(_priceFilterActive
                    ? _priceFilterLabel()
                    : 'Price'),
                selected: _priceFilterActive,
                onSelected: (_) => _showPriceFilterSheet(),
                selectedColor: AppTheme.accent,
                checkmarkColor: Colors.white,
                labelStyle: _priceFilterActive
                    ? const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)
                    : null,
                deleteIcon: _priceFilterActive
                    ? const Icon(Icons.close, size: 16, color: Colors.white)
                    : null,
                onDeleted:
                    _priceFilterActive ? _clearPriceFilter : null,
              ),
            ],
          ),
        );
      },
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  String _priceFilterLabel() {
    final min = _minPriceCtrl.text;
    final max = _maxPriceCtrl.text;
    if (min.isNotEmpty && max.isNotEmpty) return '₹$min – ₹$max';
    if (min.isNotEmpty) return '₹$min+';
    if (max.isNotEmpty) return '≤ ₹$max';
    return 'Price';
  }

  void _clearPriceFilter() {
    _minPriceCtrl.clear();
    _maxPriceCtrl.clear();
    setState(() => _priceFilterActive = false);
    context.read<CatalogBloc>().add(const CatalogPriceFilterChanged());
  }

  void _showPriceFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
              24, 20, 24, MediaQuery.of(sheetCtx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Text('Price Range (₹)',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  if (_priceFilterActive)
                    TextButton(
                      onPressed: () {
                        _clearPriceFilter();
                        Navigator.pop(sheetCtx);
                      },
                      child: const Text('Clear',
                          style: TextStyle(color: Colors.redAccent)),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _minPriceCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Minimum Price',
                  prefixText: '₹ ',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _maxPriceCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Maximum Price',
                  prefixText: '₹ ',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  final minInr = double.tryParse(_minPriceCtrl.text);
                  final maxInr = double.tryParse(_maxPriceCtrl.text);
                  if (minInr == null && maxInr == null) {
                    _clearPriceFilter();
                  } else {
                    setState(() => _priceFilterActive = true);
                    context.read<CatalogBloc>().add(
                          CatalogPriceFilterChanged(
                              minPriceInr: minInr, maxPriceInr: maxInr),
                        );
                  }
                  Navigator.pop(sheetCtx);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Apply Filter',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showTypeFilterSheet() {
    const categories = [
      'sofa',
      'table',
      'chair',
      'lighting',
      'storage',
      'bed',
      'rug',
    ];

    const categoryIcons = {
      'sofa': Icons.weekend_rounded,
      'table': Icons.table_restaurant_rounded,
      'chair': Icons.chair_rounded,
      'lighting': Icons.light_rounded,
      'storage': Icons.inventory_2_rounded,
      'bed': Icons.bed_rounded,
      'rug': Icons.grid_on_rounded,
    };

    final bloc = context.read<CatalogBloc>();
    final currentCategory =
        bloc.state is CatalogLoaded
            ? (bloc.state as CatalogLoaded).activeCategory
            : null;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Text('Furniture Type',
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  if (currentCategory != null)
                    TextButton(
                      onPressed: () {
                        context.read<CatalogBloc>().add(
                            const CatalogCategoryChanged(category: null));
                        Navigator.pop(sheetCtx);
                      },
                      child: const Text('Clear',
                          style: TextStyle(color: Colors.redAccent)),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: categories.map((cat) {
                  final isActive = cat == currentCategory;
                  return ChoiceChip(
                    avatar: Icon(
                      categoryIcons[cat] ?? Icons.chair_rounded,
                      size: 18,
                      color: isActive ? Colors.white : AppTheme.accent,
                    ),
                    label: Text(_capitalize(cat)),
                    selected: isActive,
                    selectedColor: AppTheme.accent,
                    checkmarkColor: Colors.white,
                    labelStyle: isActive
                        ? const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600)
                        : null,
                    onSelected: (_) {
                      context.read<CatalogBloc>().add(
                          CatalogCategoryChanged(
                              category: isActive ? null : cat));
                      Navigator.pop(sheetCtx);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProductCard(ProductModel product) {
    final bb = product.boundingBox;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showProductDetail(product),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Product image + wishlist heart ──
            Expanded(
              flex: 4,
              child: Stack(
                children: [
                  Container(
                    width: double.infinity,
                    color: AppTheme.surfaceDimOf(context),
                    child: product.imageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: product.imageUrl!,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Center(
                              child: Icon(
                                _categoryIcon(product.category),
                                size: 36,
                                color: AppTheme.mutedOf(context).withAlpha(80),
                              ),
                            ),
                            errorWidget: (_, __, ___) =>
                                _cardIconFallback(product),
                          )
                        : _cardIconFallback(product),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => _toggleWishlist(product.id),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surface
                              .withOpacity(0.85),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _wishlistIds.contains(product.id)
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 18,
                          color: _wishlistIds.contains(product.id)
                              ? AppTheme.accent
                              : AppTheme.mutedOf(context),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ── Dimensions label ──────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              color: AppTheme.surfaceDimOf(context),
              child: Text(
                bb.displayString,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.secondaryTextOf(context),
                ),
              ),
            ),
            // ── Info ──────────────────────
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      product.color.isNotEmpty ? product.color : product.category,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.secondaryTextOf(context),
                      ),
                      maxLines: 1,
                    ),
                    const Spacer(),
                    Text(
                      product.priceFormatted,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppTheme.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardIconFallback(ProductModel product) {
    return Center(
      child: Icon(
        _categoryIcon(product.category),
        size: 40,
        color: AppTheme.mutedOf(context),
      ),
    );
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'sofa':
        return Icons.weekend_outlined;
      case 'table':
        return Icons.table_restaurant_outlined;
      case 'chair':
        return Icons.chair_outlined;
      case 'lighting':
        return Icons.light_outlined;
      case 'storage':
        return Icons.shelves;
      case 'bed':
        return Icons.bed_outlined;
      case 'rug':
        return Icons.rectangle_outlined;
      default:
        return Icons.inventory_2_outlined;
    }
  }

  void _showProductDetail(ProductModel product) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.handleOf(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── 3D Model Viewer ────────────
              Container(
                height: 250,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceDimOf(context),
                  borderRadius: BorderRadius.circular(16),
                ),
                clipBehavior: Clip.antiAlias,
                child: product.modelFile != null
                    ? ModelViewer(
                        backgroundColor:
                            const Color(0xFFF5F5F5),
                        src: product.modelFile!,
                        alt: product.name,
                        ar: false,
                        autoRotate: true,
                        autoRotateDelay: 0,
                        rotationPerSecond: '30deg',
                        cameraControls: true,
                        disableZoom: false,
                      )
                    : _build3DPlaceholder(product),
              ),
              const SizedBox(height: 16),

              // Name + Price row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: Theme.of(ctx).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          product.color.isNotEmpty
                              ? '${product.category[0].toUpperCase()}${product.category.substring(1)} · ${product.color}'
                              : product.category[0].toUpperCase() +
                                  product.category.substring(1),
                          style: TextStyle(
                            color: AppTheme.secondaryTextOf(context),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withAlpha(25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      product.priceFormatted,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.accent,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Visual Dimensions Diagram ──
              _buildDimensionsDiagram(product),
              const SizedBox(height: 16),

              // Description
              if (product.description.isNotEmpty) ...[
                Text(
                  product.description,
                  style: Theme.of(ctx).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
              ],

              // Tags
              if (product.tags.isNotEmpty)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: product.tags
                      .map((tag) => Chip(
                            label: Text(tag, style: const TextStyle(fontSize: 12)),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            side: BorderSide.none,
                            backgroundColor: AppTheme.surfaceDimOf(context),
                          ))
                      .toList(),
                ),
              const SizedBox(height: 24),

              // Action buttons
              BlocBuilder<CatalogBloc, CatalogState>(
                builder: (context, catState) {
                  String? roomId;
                  String? roomName;
                  if (catState is CatalogLoaded && catState.hasRoomFilter) {
                    roomId = catState.filterRoomId;
                    roomName = catState.filterRoomName;
                  }
                  return Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            if (roomId != null && roomName != null) {
                              _runFitCheck(product, roomId, roomName);
                            } else {
                              _showRoomPicker(product);
                            }
                          },
                          icon: const Icon(Icons.check_circle_outline),
                          label: Text(roomId != null
                              ? 'Check Fit in $roomName'
                              : 'Check Fit'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.success,
                            minimumSize: const Size(0, 48),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _build3DPlaceholder(ProductModel product) {
    return Stack(
      children: [
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _categoryIcon(product.category),
                size: 64,
                color: AppTheme.mutedOf(context).withAlpha(100),
              ),
              const SizedBox(height: 8),
              Text(
                product.boundingBox.displayString,
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.mutedOf(context).withAlpha(150),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          bottom: 8,
          right: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              '3D model coming soon',
              style: TextStyle(fontSize: 10, color: Colors.black38),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDimensionsDiagram(ProductModel product) {
    final bb = product.boundingBox;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceDimOf(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.straighten, size: 16, color: AppTheme.secondaryTextOf(context)),
              const SizedBox(width: 6),
              const Text(
                'Dimensions (3D)',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: RoomDimensionView(
              widthM: bb.widthM,
              lengthM: bb.depthM,
              heightM: bb.heightM,
              size: 150,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.crop_square, size: 14, color: AppTheme.secondaryTextOf(context)),
              const SizedBox(width: 6),
              Text(
                'Footprint: ${(bb.widthM * bb.depthM).toStringAsFixed(2)} m²  ·  '
                '${DimensionFormatter.format(bb.widthM)} × ${DimensionFormatter.format(bb.depthM)}',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.secondaryTextOf(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Room Picker & Fit-Check Flow ──────────────────────────────────────────

  void _showRoomPicker(ProductModel product) async {
    List<RoomModel>? rooms;
    String? error;

    try {
      final repo = GetIt.instance<RoomRepository>();
      rooms = await repo.getUserRooms();
    } catch (e) {
      error = e.toString();
    }

    if (!mounted) return;

    if (error != null || rooms == null || rooms.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(rooms?.isEmpty == true
              ? 'No rooms found. Add a room first!'
              : 'Error loading rooms: $error'),
          action: rooms?.isEmpty == true
              ? SnackBarAction(
                  label: 'Add Room',
                  onPressed: () => context.push('/manual-room'),
                )
              : null,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.handleOf(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Select a Room',
                style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Check if "${product.name}" fits',
                style: TextStyle(color: AppTheme.secondaryTextOf(context), fontSize: 13)),
            const SizedBox(height: 16),
            ...rooms!.where((r) => r.isCompleted).map((room) {
              final dims = room.dimensions;
              final w = dims?['width_m'] as num?;
              final l = dims?['length_m'] as num?;
              return ListTile(
                leading: Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.meeting_room_outlined,
                      color: AppTheme.primary, size: 22),
                ),
                title: Text(room.roomName),
                subtitle: w != null && l != null
                    ? Text('${w.toStringAsFixed(1)} × ${l.toStringAsFixed(1)}m')
                    : null,
                trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                onTap: () {
                  Navigator.pop(ctx);
                  _runFitCheck(product, room.id, room.roomName);
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _runFitCheck(ProductModel product, String roomId, String roomName) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final repo = GetIt.instance<CatalogRepository>();
      final result = await repo.checkFit(
        roomId: roomId,
        productId: product.id,
      );

      if (!mounted) return;
      Navigator.pop(context); // dismiss loading

      _showFitCheckResult(product, roomName, result);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fit-check error: $e'),
            backgroundColor: AppTheme.error),
      );
    }
  }

  void _showFitCheckResult(
      ProductModel product, String roomName, Map<String, dynamic> result) {
    final fits = result['fits'] as bool? ?? false;
    final verdict = result['verdict'] as String? ?? (fits ? 'fits' : 'tight_fit');
    final designScore = result['design_score'] as int? ?? 0;
    final suggestion = result['suggestion'] as String?;
    final fillPercent = result['room_fill_percent'] as num?;
    final collisions = result['collisions'] as List<dynamic>? ?? [];
    final warnings = result['warnings'] as List<dynamic>? ?? [];
    final clearance = result['clearance'] as Map<String, dynamic>?;
    final roomDims = result['room_dimensions'] as Map<String, dynamic>?;
    final placement = result['placement_used'] as Map<String, dynamic>?;

    final isTooLarge = verdict == 'too_large';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: isTooLarge ? 0.50 : 0.65,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, sc) => SingleChildScrollView(
          controller: sc,
          padding: const EdgeInsets.all(24),
          child: isTooLarge
              ? _buildTooLargeView(ctx, product, roomName, result)
              : _buildDetailedFitView(
                  ctx, product, roomName, fits, designScore, suggestion,
                  fillPercent, collisions, warnings, clearance, roomDims,
                  placement),
        ),
      ),
    );
  }

  Widget _buildTooLargeView(
      BuildContext ctx, ProductModel product, String roomName,
      Map<String, dynamic> result) {
    final fillPercent = result['room_fill_percent'] as num? ?? 0;
    final suggestion = result['suggestion'] as String?;
    final roomDims = result['room_dimensions'] as Map<String, dynamic>?;
    final placement = result['placement_used'] as Map<String, dynamic>?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Center(
          child: Container(width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppTheme.handleOf(context),
                borderRadius: BorderRadius.circular(2),
              )),
        ),
        const SizedBox(height: 24),

        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color: AppTheme.error.withAlpha(25),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.zoom_out_map, size: 44, color: AppTheme.error),
        ),
        const SizedBox(height: 16),
        Text(
          'Too Large',
          style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppTheme.error,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          '"${product.name}" in $roomName',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.secondaryTextOf(context), fontSize: 13),
        ),
        const SizedBox(height: 20),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.error.withAlpha(15),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.error.withAlpha(40)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(Icons.straighten, size: 18, color: AppTheme.error),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Furniture: ${DimensionFormatter.formatCompact(product.boundingBox.widthM, product.boundingBox.depthM, product.boundingBox.heightM)}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.home_outlined, size: 18, color: AppTheme.secondaryTextOf(context)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Room: ${DimensionFormatter.formatCompact(
                        (roomDims?['width_m'] as num?)?.toDouble() ?? 0,
                        (roomDims?['length_m'] as num?)?.toDouble() ?? 0,
                        (roomDims?['height_m'] as num?)?.toDouble() ?? 0,
                      )}',
                      style: TextStyle(fontSize: 13, color: AppTheme.secondaryTextOf(context)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.pie_chart_outline, size: 18, color: AppTheme.error),
                  const SizedBox(width: 10),
                  Text(
                    'Would cover ${fillPercent.toStringAsFixed(0)}% of floor area',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.error),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (roomDims != null)
          Center(
            child: RepaintBoundary(
              key: _diagramKey,
              child: FurnitureInRoomView(
                roomWidthM: (roomDims['width_m'] as num?)?.toDouble() ?? 3.0,
                roomLengthM: (roomDims['length_m'] as num?)?.toDouble() ?? 3.0,
                roomHeightM: (roomDims['height_m'] as num?)?.toDouble() ?? 2.5,
                furnitureWidthM: product.boundingBox.widthM,
                furnitureLengthM: product.boundingBox.depthM,
                furnitureHeightM: product.boundingBox.heightM,
                size: 240,
                placementX: (placement?['x'] as num?)?.toDouble(),
                placementZ: (placement?['z'] as num?)?.toDouble(),
                placementRotation: (placement?['rotation_y'] as num?)?.toDouble(),
              ),
            ),
          ),
        const SizedBox(height: 16),

        if (suggestion != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.accent.withAlpha(20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.lightbulb_outline, size: 18, color: AppTheme.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(suggestion,
                      style: TextStyle(fontSize: 13, color: AppTheme.accent)),
                ),
              ],
            ),
          ),
        const SizedBox(height: 20),
        _buildShareButton(product, roomName, result),
      ],
    );
  }

  Widget _buildDetailedFitView(
      BuildContext ctx, ProductModel product, String roomName,
      bool fits, int designScore, String? suggestion, num? fillPercent,
      List<dynamic> collisions, List<dynamic> warnings,
      Map<String, dynamic>? clearance, Map<String, dynamic>? roomDims,
      Map<String, dynamic>? placement) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppTheme.handleOf(context),
                borderRadius: BorderRadius.circular(2),
              )),
        ),
        const SizedBox(height: 20),

        // Result header
        Center(
          child: Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: fits
                  ? AppTheme.success.withAlpha(30)
                  : AppTheme.error.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: Icon(
              fits ? Icons.check_circle : Icons.cancel,
              size: 40,
              color: fits ? AppTheme.success : AppTheme.error,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            fits ? 'It Fits!' : 'Tight Fit',
            style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: fits ? AppTheme.success : AppTheme.error,
                ),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            '"${product.name}" in $roomName',
            style: TextStyle(color: AppTheme.secondaryTextOf(context), fontSize: 13),
          ),
        ),
        const SizedBox(height: 20),

        // Design Score
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surfaceDimOf(context),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 54, height: 54,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: designScore / 100,
                      strokeWidth: 5,
                      backgroundColor: AppTheme.handleOf(context),
                      color: designScore >= 70
                          ? AppTheme.success
                          : designScore >= 40
                              ? Colors.orange
                              : AppTheme.error,
                    ),
                    Text('$designScore',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 16)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Design Score',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    if (fillPercent != null)
                      Text(
                        'Fills ${fillPercent.toStringAsFixed(0)}% of floor area',
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.secondaryTextOf(context)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Placement strategy info
        if (placement != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.primary.withAlpha(15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.auto_fix_high, size: 16, color: AppTheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'AI Placement: ${_strategyLabel(placement['strategy'] as String?)} position',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),

        // 3D Furniture-in-Room Visualization
        if (roomDims != null) ...[
          const Text('Furniture vs. Room',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 8),
          Center(
            child: RepaintBoundary(
              key: _diagramKey,
              child: FurnitureInRoomView(
                roomWidthM:
                    (roomDims['width_m'] as num?)?.toDouble() ?? 3.0,
                roomLengthM:
                    (roomDims['length_m'] as num?)?.toDouble() ?? 3.0,
                roomHeightM:
                    (roomDims['height_m'] as num?)?.toDouble() ?? 2.5,
                furnitureWidthM: product.boundingBox.widthM,
                furnitureLengthM: product.boundingBox.depthM,
                furnitureHeightM: product.boundingBox.heightM,
                size: 280,
                placementX: (placement?['x'] as num?)?.toDouble(),
                placementZ: (placement?['z'] as num?)?.toDouble(),
                placementRotation:
                    (placement?['rotation_y'] as num?)?.toDouble(),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Clearance
        if (clearance != null) ...[
          const Text('Wall Clearance',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _clearanceChip('N', clearance['north_m']),
              _clearanceChip('S', clearance['south_m']),
              _clearanceChip('E', clearance['east_m']),
              _clearanceChip('W', clearance['west_m']),
            ],
          ),
          const SizedBox(height: 16),
        ],

        // Collisions
        if (collisions.isNotEmpty) ...[
          Text('Collisions (${collisions.length})',
              style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: Colors.red)),
          const SizedBox(height: 8),
          ...collisions.map((c) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber, size: 16, color: AppTheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(c['description'] ?? '',
                          style: const TextStyle(fontSize: 13)),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 12),
        ],

        // Warnings
        if (warnings.isNotEmpty) ...[
          const Text('Design Warnings',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: Colors.orange)),
          const SizedBox(height: 8),
          ...warnings.map((w) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      w['severity'] == 'warning'
                          ? Icons.warning
                          : Icons.info_outline,
                      size: 16,
                      color: w['severity'] == 'warning'
                          ? Colors.orange
                          : Colors.blue,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(w['message'] ?? '',
                          style: const TextStyle(fontSize: 13)),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 12),
        ],

        // Suggestion
        if (suggestion != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.accent.withAlpha(20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.lightbulb_outline,
                    size: 18, color: AppTheme.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(suggestion,
                      style:
                          TextStyle(fontSize: 13, color: AppTheme.accent)),
                ),
              ],
            ),
          ),
        const SizedBox(height: 20),
        _buildShareButton(product, roomName, {
          'fits': fits,
          'verdict': fits ? 'fits' : 'tight_fit',
          'design_score': designScore,
          'suggestion': suggestion,
          'room_fill_percent': fillPercent,
          'clearance': clearance,
          'room_dimensions': roomDims,
        }),
        const SizedBox(height: 10),
        Row(
          children: [
            if (fits)
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.view_in_ar_rounded, size: 18),
                  label: const Text('View in AR'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    final bb = product.boundingBox;
                    context.push(
                      '${AppRoutes.arPreview}'
                      '?productName=${Uri.encodeComponent(product.name)}'
                      '&widthM=${bb.widthM}&depthM=${bb.depthM}&heightM=${bb.heightM}'
                      '${product.imageUrl != null ? '&modelUrl=${Uri.encodeComponent(product.imageUrl!)}' : ''}',
                    );
                  },
                ),
              ),
            if (fits) const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: const Text('Add More'),
                onPressed: () {
                  Navigator.pop(ctx);
                  context.push(AppRoutes.layoutPlanner);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildShareButton(
      ProductModel product, String roomName, Map<String, dynamic> result) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
        label: const Text('Share Report'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 46),
        ),
        onPressed: () => _exportPdf(product, roomName, result),
      ),
    );
  }

  Future<void> _exportPdf(
      ProductModel product, String roomName, Map<String, dynamic> result) async {
    final fits = result['fits'] as bool? ?? false;
    final verdict = result['verdict'] as String? ?? 'fits';
    final designScore = result['design_score'] as int? ?? 0;
    final suggestion = result['suggestion'] as String?;
    final fillPercent = (result['room_fill_percent'] as num?)?.toDouble() ?? 0;
    final clearance = result['clearance'] as Map<String, dynamic>?;
    final roomDims = result['room_dimensions'] as Map<String, dynamic>?;

    try {
      await PdfExportService.generateAndShare(
        roomName: roomName,
        roomDims: {
          'width': (roomDims?['width_m'] as num?)?.toDouble() ?? 0,
          'length': (roomDims?['length_m'] as num?)?.toDouble() ?? 0,
          'height': (roomDims?['height_m'] as num?)?.toDouble() ?? 0,
        },
        productName: product.name,
        productCategory: product.category,
        productDims: {
          'width': product.boundingBox.widthM,
          'depth': product.boundingBox.depthM,
          'height': product.boundingBox.heightM,
        },
        fits: fits,
        verdict: verdict,
        designScore: designScore,
        clearance: {
          'north': (clearance?['north_m'] as num?)?.toDouble() ?? 0,
          'south': (clearance?['south_m'] as num?)?.toDouble() ?? 0,
          'east': (clearance?['east_m'] as num?)?.toDouble() ?? 0,
          'west': (clearance?['west_m'] as num?)?.toDouble() ?? 0,
        },
        fillPercent: fillPercent,
        suggestion: suggestion,
        diagramKey: _diagramKey,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'),
              backgroundColor: AppTheme.error),
        );
      }
    }
  }

  String _strategyLabel(String? strategy) {
    switch (strategy) {
      case 'against_wall':
        return 'Against wall';
      case 'center':
        return 'Room center';
      case 'corner':
        return 'Corner';
      case 'near_wall':
        return 'Near wall';
      case 'manual':
        return 'Manual';
      default:
        return 'Auto';
    }
  }

  static const _compassColors = {
    'N': Color(0xFF5C9DFF),
    'S': Color(0xFFFFD54F),
    'E': Color(0xFF81C784),
    'W': Color(0xFFCE93D8),
  };

  Widget _clearanceChip(String direction, dynamic meters) {
    final m = (meters as num?)?.toDouble() ?? 0;
    final clamped = m < 0 ? 0.0 : m;
    final dirColor = _compassColors[direction] ?? Colors.white;

    final String label;
    final Color valueColor;

    if (clamped <= 0.01) {
      label = 'Flush';
      valueColor = Colors.grey;
    } else if (clamped < 0.6) {
      label = DimensionFormatter.format(clamped);
      valueColor = AppTheme.error;
    } else if (clamped < 0.9) {
      label = DimensionFormatter.format(clamped);
      valueColor = Colors.orange;
    } else {
      label = DimensionFormatter.format(clamped);
      valueColor = AppTheme.success;
    }

    return Column(
      children: [
        Text(direction,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: dirColor)),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: valueColor.withAlpha(25),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: dirColor.withAlpha(60), width: 1),
          ),
          child: Text(label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: valueColor)),
        ),
      ],
    );
  }

  Widget _buildUnitToggle() {
    return PopupMenuButton<DimensionUnit>(
      icon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.straighten, size: 18, color: AppTheme.secondaryTextOf(context)),
          const SizedBox(width: 2),
          Text(
            DimensionFormatter.unitLabel().toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppTheme.primary,
            ),
          ),
        ],
      ),
      onSelected: (unit) {
        DimensionFormatter.currentUnit.value = unit;
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: DimensionUnit.meters,
          child: Row(
            children: [
              if (DimensionFormatter.currentUnit.value == DimensionUnit.meters)
                Icon(Icons.check, size: 16, color: AppTheme.primary)
              else
                const SizedBox(width: 16),
              const SizedBox(width: 8),
              const Text('Meters (m)'),
            ],
          ),
        ),
        PopupMenuItem(
          value: DimensionUnit.feet,
          child: Row(
            children: [
              if (DimensionFormatter.currentUnit.value == DimensionUnit.feet)
                Icon(Icons.check, size: 16, color: AppTheme.primary)
              else
                const SizedBox(width: 16),
              const SizedBox(width: 8),
              const Text('Feet (ft)'),
            ],
          ),
        ),
        PopupMenuItem(
          value: DimensionUnit.inches,
          child: Row(
            children: [
              if (DimensionFormatter.currentUnit.value == DimensionUnit.inches)
                Icon(Icons.check, size: 16, color: AppTheme.primary)
              else
                const SizedBox(width: 16),
              const SizedBox(width: 8),
              const Text('Inches (")'),
            ],
          ),
        ),
      ],
    );
  }
}

