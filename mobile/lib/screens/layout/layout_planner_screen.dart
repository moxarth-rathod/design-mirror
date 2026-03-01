import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../config/theme.dart';
import '../../config/units.dart';
import '../../models/room_model.dart';
import '../../models/product_model.dart';
import '../../repositories/room_repository.dart';
import '../../repositories/catalog_repository.dart';

class LayoutPlannerScreen extends StatefulWidget {
  const LayoutPlannerScreen({super.key});

  @override
  State<LayoutPlannerScreen> createState() => _LayoutPlannerScreenState();
}

class _PlacedItem {
  final ProductModel product;
  double xM = 0;
  double zM = 0;
  double rotationY = 0;
  bool fits = true;
  int designScore = 100;
  List<Map<String, dynamic>> collisions = const [];

  _PlacedItem({required this.product});

  static const _floorCategories = {'rug', 'carpet', 'mat'};
  bool get isFloorItem =>
      _floorCategories.contains(product.category.toLowerCase()) ||
      product.tags.any((t) => _floorCategories.contains(t.toLowerCase()));

  bool get isRotated => (rotationY ~/ 90) % 2 == 1;
  double get effectiveW => isRotated ? product.boundingBox.depthM : product.boundingBox.widthM;
  double get effectiveD => isRotated ? product.boundingBox.widthM : product.boundingBox.depthM;
}

class _LayoutPlannerScreenState extends State<LayoutPlannerScreen> {
  List<RoomModel>? _rooms;
  RoomModel? _selectedRoom;
  final List<_PlacedItem> _placedItems = [];
  List<ProductModel>? _catalogProducts;
  Map<String, dynamic>? _results;
  bool _loading = false;
  bool _checking = false;
  String _searchQuery = '';

  static const _furnitureColors = [
    Color(0xFF2196F3),
    Color(0xFFFF9800),
    Color(0xFF4CAF50),
    Color(0xFF9C27B0),
    Color(0xFF009688),
    Color(0xFFE91E63),
    Color(0xFF795548),
    Color(0xFF607D8B),
  ];

  @override
  void initState() {
    super.initState();
    _loadRooms();
    _loadCatalog();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPreselectedRoom());
  }

  void _checkPreselectedRoom() {
    final uri = GoRouterState.of(context).uri;
    final preRoomId = uri.queryParameters['roomId'] ?? uri.queryParameters['room_id'];
    if (preRoomId != null && _rooms != null) {
      final match = _rooms!.where((r) => r.id == preRoomId).toList();
      if (match.isNotEmpty) setState(() => _selectedRoom = match.first);
    }
  }

  Future<void> _loadRooms() async {
    setState(() => _loading = true);
    try {
      final repo = GetIt.instance<RoomRepository>();
      final rooms = await repo.getUserRooms();
      if (mounted) {
        setState(() => _rooms = rooms);
        _checkPreselectedRoom();
      }
    } catch (_) {
      if (mounted) setState(() => _rooms = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadCatalog() async {
    try {
      final repo = GetIt.instance<CatalogRepository>();
      final page = await repo.getCatalog(
        page: 1,
        pageSize: 50,
        search: _searchQuery.isEmpty ? null : _searchQuery,
      );
      if (mounted) setState(() => _catalogProducts = page.items);
    } catch (_) {
      if (mounted) setState(() => _catalogProducts = []);
    }
  }

  void _onSearchChanged(String query) {
    setState(() => _searchQuery = query);
    _loadCatalog();
  }

  double get _roomW => (_selectedRoom?.dimensions?['width_m'] as num?)?.toDouble() ?? 4.0;
  double get _roomL => (_selectedRoom?.dimensions?['length_m'] as num?)?.toDouble() ?? 5.0;

  void _addProduct(ProductModel product) {
    final item = _PlacedItem(product: product);
    _smartPlace(item);
    setState(() {
      _placedItems.add(item);
      _results = null;
    });
  }

  void _smartPlace(_PlacedItem item) {
    final rw = _roomW;
    final rl = _roomL;
    final fw = item.effectiveW;
    final fd = item.effectiveD;
    final margin = 0.05;

    if (item.isFloorItem) {
      item.xM = (rw - fw) / 2;
      item.zM = (rl - fd) / 2;
      return;
    }

    final occupied = _placedItems.where((p) => p != item).toList();
    double bestX = margin, bestZ = margin;
    double bestScore = -999;

    final candidates = <Offset>[
      Offset(margin, rl - fd - margin),
      Offset(rw - fw - margin, rl - fd - margin),
      Offset(margin, margin),
      Offset(rw - fw - margin, margin),
      Offset((rw - fw) / 2, rl - fd - margin),
      Offset((rw - fw) / 2, margin),
      Offset(margin, (rl - fd) / 2),
      Offset(rw - fw - margin, (rl - fd) / 2),
      Offset((rw - fw) / 2, (rl - fd) / 2),
    ];

    for (final c in candidates) {
      if (c.dx < 0 || c.dy < 0 || c.dx + fw > rw || c.dy + fd > rl) continue;
      double score = 10;
      bool overlaps = false;
      for (final occ in occupied) {
        if (occ.isFloorItem) continue;
        if (_rectsOverlap(c.dx, c.dy, fw, fd, occ.xM, occ.zM,
            occ.effectiveW, occ.effectiveD)) {
          overlaps = true;
          break;
        }
        final dist = (c.dx - occ.xM).abs() + (c.dy - occ.zM).abs();
        score += dist.clamp(0, 5);
      }
      if (!overlaps && score > bestScore) {
        bestScore = score;
        bestX = c.dx;
        bestZ = c.dy;
      }
    }
    item.xM = bestX;
    item.zM = bestZ;
  }

  bool _rectsOverlap(double x1, double z1, double w1, double d1,
      double x2, double z2, double w2, double d2) {
    return x1 < x2 + w2 && x1 + w1 > x2 && z1 < z2 + d2 && z1 + d1 > z2;
  }

  void _removeProduct(int index) {
    setState(() {
      _placedItems.removeAt(index);
      _results = null;
    });
  }

  Future<void> _checkLayout() async {
    if (_selectedRoom == null || _placedItems.isEmpty) return;
    setState(() => _checking = true);
    _results = null;
    try {
      final repo = GetIt.instance<RoomRepository>();
      final halfW = _roomW / 2;
      final halfL = _roomL / 2;
      final items = _placedItems.map((p) {
        final cx = p.xM + p.effectiveW / 2 - halfW;
        final cz = p.zM + p.effectiveD / 2 - halfL;
        return {
          'product_id': p.product.id,
          'position': {'x': cx, 'z': cz, 'rotation_y': p.rotationY},
        };
      }).toList();
      final result = await repo.checkMultiFit(
        roomId: _selectedRoom!.id,
        items: items,
      );
      if (mounted) {
        final resultItems = result['items'] as List<dynamic>? ?? [];
        for (int i = 0; i < resultItems.length && i < _placedItems.length; i++) {
          final ri = resultItems[i] as Map<String, dynamic>;
          _placedItems[i].fits = ri['fits'] as bool? ?? false;
          _placedItems[i].designScore = (ri['design_score'] as num?)?.toInt() ?? 0;
          _placedItems[i].collisions = (ri['collisions'] as List<dynamic>?)
              ?.map((c) => c as Map<String, dynamic>)
              .toList() ?? [];
          final pu = ri['placement_used'] as Map<String, dynamic>?;
          if (pu != null) {
            final px = (pu['x'] as num?)?.toDouble() ?? 0;
            final pz = (pu['z'] as num?)?.toDouble() ?? 0;
            _placedItems[i].xM = px + halfW - _placedItems[i].effectiveW / 2;
            _placedItems[i].zM = pz + halfL - _placedItems[i].effectiveD / 2;
          }
        }
        setState(() => _results = result);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Layout Planner'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        actions: [
          if (_selectedRoom != null && _placedItems.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.fullscreen),
              tooltip: 'Interactive editor',
              onPressed: _openInteractiveEditor,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildRoomSelection(),
                  const SizedBox(height: 16),
                  _buildFurnitureSelection(),
                  const SizedBox(height: 16),
                  _buildLayoutPreview(),
                  const SizedBox(height: 16),
                  _buildCheckButton(),
                  if (_results != null) ...[
                    const SizedBox(height: 16),
                    _buildResultsSection(),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildRoomSelection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('1. Select Room', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (_selectedRoom != null)
              Chip(
                label: Text(
                  '${_selectedRoom!.roomName} — ${DimensionFormatter.format(_roomW)} × ${DimensionFormatter.format(_roomL)}',
                ),
                deleteIcon: const Icon(Icons.close, size: 18),
                onDeleted: () => setState(() {
                  _selectedRoom = null;
                  _results = null;
                  _placedItems.clear();
                }),
                backgroundColor: AppTheme.accent.withAlpha(51),
              )
            else if (_rooms == null || _rooms!.isEmpty)
              Text('No rooms yet. Create a room first.',
                  style: TextStyle(color: AppTheme.secondaryTextOf(context)))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _rooms!.where((r) => r.dimensions != null).map((room) {
                  final w = room.dimensions?['width_m'] as num?;
                  final l = room.dimensions?['length_m'] as num?;
                  return ActionChip(
                    label: Text('${room.roomName} (${DimensionFormatter.format(w?.toDouble() ?? 0)} × ${DimensionFormatter.format(l?.toDouble() ?? 0)})'),
                    onPressed: () => setState(() => _selectedRoom = room),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFurnitureSelection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('2. Add Furniture', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(
                hintText: 'Search catalog...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: _onSearchChanged,
            ),
            const SizedBox(height: 12),
            if (_catalogProducts != null && _catalogProducts!.isNotEmpty)
              SizedBox(
                height: 140,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _catalogProducts!.length,
                  itemBuilder: (context, i) {
                    final p = _catalogProducts![i];
                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: _ProductCard(product: p, onTap: () => _addProduct(p)),
                    );
                  },
                ),
              ),
            if (_placedItems.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(_placedItems.length, (i) {
                  final p = _placedItems[i];
                  final color = _furnitureColors[i % _furnitureColors.length];
                  return Chip(
                    avatar: CircleAvatar(backgroundColor: color, radius: 8),
                    label: Text(p.product.name),
                    deleteIcon: const Icon(Icons.close, size: 18),
                    onDeleted: () => _removeProduct(i),
                    side: _results != null
                        ? BorderSide(color: p.fits ? AppTheme.success : AppTheme.error, width: 2)
                        : BorderSide.none,
                  );
                }),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLayoutPreview() {
    if (_selectedRoom == null || _placedItems.isEmpty) {
      return Card(
        child: Container(
          height: 200,
          alignment: Alignment.center,
          child: Text('Select a room and add furniture',
              style: TextStyle(color: AppTheme.secondaryTextOf(context))),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('3. Layout Preview', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.open_in_full, size: 16),
                  label: const Text('Edit'),
                  onPressed: _openInteractiveEditor,
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 240,
              child: CustomPaint(
                painter: _LayoutPreviewPainter(
                  roomWidthM: _roomW,
                  roomLengthM: _roomL,
                  items: _placedItems,
                  colors: _furnitureColors,
                ),
                size: Size.infinite,
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text('Tap "Edit" to drag furniture around',
                  style: TextStyle(fontSize: 11, color: AppTheme.secondaryTextOf(context))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckButton() {
    final canCheck = _selectedRoom != null && _placedItems.isNotEmpty && !_checking;
    return FilledButton.icon(
      onPressed: canCheck ? _checkLayout : null,
      icon: _checking
          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.check_circle_outline),
      label: Text(_checking ? 'Checking...' : 'Check Layout'),
    );
  }

  Widget _buildResultsSection() {
    final items = _results?['items'] as List<dynamic>? ?? [];
    final fillPct = (_results?['total_fill_percent'] as num?)?.toDouble() ?? 0;
    final overallScore = (_results?['overall_score'] as num?)?.toInt() ?? 0;
    final overallFits = _results?['overall_fits'] as bool? ?? false;
    final combinedWarnings = _results?['combined_warnings'] as List<dynamic>? ?? [];
    final interCollisions = _results?['inter_collisions'] as List<dynamic>? ?? [];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  overallFits ? Icons.check_circle : Icons.cancel,
                  color: overallFits ? AppTheme.success : AppTheme.error,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Text(
                  overallFits ? 'Layout Fits!' : 'Issues Found',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: overallFits ? AppTheme.success : AppTheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _statChip('Score', '$overallScore', overallScore >= 70 ? AppTheme.success : AppTheme.error),
                const SizedBox(width: 12),
                _statChip('Floor Fill', '${fillPct.toStringAsFixed(0)}%',
                    fillPct > 60 ? AppTheme.error : (fillPct > 40 ? Colors.orange : AppTheme.success)),
                const SizedBox(width: 12),
                _statChip('Items', '${items.length}', AppTheme.primary),
              ],
            ),
            const SizedBox(height: 16),
            ...items.asMap().entries.map((e) {
              final idx = e.key;
              final item = e.value as Map<String, dynamic>;
              final fits = item['fits'] as bool? ?? false;
              final name = item['product_name'] as String? ?? 'Unknown';
              final score = (item['design_score'] as num?)?.toInt() ?? 0;
              final cols = item['collisions'] as List<dynamic>? ?? [];
              final color = _furnitureColors[idx % _furnitureColors.length];
              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: color,
                  child: Icon(
                    fits ? Icons.check : Icons.close,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: cols.isNotEmpty
                    ? Text(
                        (cols.first as Map<String, dynamic>)['description'] as String? ?? '',
                        style: TextStyle(fontSize: 11, color: AppTheme.error),
                      )
                    : null,
                trailing: Text('$score', style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: score >= 70 ? AppTheme.success : AppTheme.error,
                )),
              );
            }),
            if (interCollisions.isNotEmpty) ...[
              const Divider(),
              Text('Furniture Conflicts', style: TextStyle(color: AppTheme.error, fontWeight: FontWeight.w600, fontSize: 13)),
              ...interCollisions.map((c) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(children: [
                      Icon(Icons.warning_amber, size: 16, color: AppTheme.error),
                      const SizedBox(width: 6),
                      Expanded(child: Text(
                        (c as Map<String, dynamic>)['description'] as String? ?? '',
                        style: TextStyle(fontSize: 12, color: AppTheme.secondaryTextOf(context)),
                      )),
                    ]),
                  )),
            ],
            if (combinedWarnings.isNotEmpty) ...[
              const Divider(),
              ...combinedWarnings.map((w) {
                final msg = (w as Map<String, dynamic>)['message'] as String? ?? '';
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.orange),
                    const SizedBox(width: 6),
                    Expanded(child: Text(msg, style: TextStyle(fontSize: 12, color: AppTheme.secondaryTextOf(context)))),
                  ]),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statChip(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(children: [
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11, color: color)),
        ]),
      ),
    );
  }

  void _openInteractiveEditor() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _InteractiveLayoutEditor(
        roomWidthM: _roomW,
        roomLengthM: _roomL,
        items: _placedItems,
        colors: _furnitureColors,
        onDone: () {
          setState(() => _results = null);
          Navigator.of(context).pop();
        },
        onCheck: () async {
          Navigator.of(context).pop();
          await _checkLayout();
        },
      ),
    ));
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Interactive Fullscreen Editor — drag furniture on the room floor plan
// ═════════════════════════════════════════════════════════════════════════════

class _InteractiveLayoutEditor extends StatefulWidget {
  final double roomWidthM;
  final double roomLengthM;
  final List<_PlacedItem> items;
  final List<Color> colors;
  final VoidCallback onDone;
  final VoidCallback onCheck;

  const _InteractiveLayoutEditor({
    required this.roomWidthM,
    required this.roomLengthM,
    required this.items,
    required this.colors,
    required this.onDone,
    required this.onCheck,
  });

  @override
  State<_InteractiveLayoutEditor> createState() => _InteractiveLayoutEditorState();
}

class _InteractiveLayoutEditorState extends State<_InteractiveLayoutEditor> {
  int _selectedIdx = -1;
  double _scale = 1.0;

  late double _pixelScale;
  late double _roomPxW;
  late double _roomPxH;
  late double _baseOffsetX;
  late double _baseOffsetZ;

  void _computeLayout(Size size) {
    const pad = 48.0;
    final aw = size.width - pad * 2;
    final ah = size.height - pad * 2;
    final sx = aw / widget.roomWidthM;
    final sz = ah / widget.roomLengthM;
    _pixelScale = math.min(sx, sz);
    _roomPxW = widget.roomWidthM * _pixelScale;
    _roomPxH = widget.roomLengthM * _pixelScale;
    _baseOffsetX = pad + (aw - _roomPxW) / 2;
    _baseOffsetZ = pad + (ah - _roomPxH) / 2;
  }

  Offset _meterToPixel(double xM, double zM) {
    return Offset(
      _baseOffsetX + xM * _pixelScale,
      _baseOffsetZ + zM * _pixelScale,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
        title: const Text('Arrange Furniture'),
        actions: [
          TextButton(
            onPressed: widget.onCheck,
            child: const Text('Check', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w700)),
          ),
          TextButton(
            onPressed: widget.onDone,
            child: const Text('Done', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
      body: LayoutBuilder(builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight - 80);
        _computeLayout(size);

        return Column(
          children: [
            Expanded(
              child: GestureDetector(
                onScaleUpdate: (d) {
                  setState(() {
                    _scale = (_scale * d.scale).clamp(0.5, 3.0);
                  });
                },
                child: Stack(
                  children: [
                    CustomPaint(
                      painter: _InteractivePainter(
                        roomWidthM: widget.roomWidthM,
                        roomLengthM: widget.roomLengthM,
                        items: widget.items,
                        colors: widget.colors,
                        selectedIdx: _selectedIdx,
                        scale: _scale,
                      ),
                      size: size,
                    ),
                    ...List.generate(widget.items.length, (i) {
                      final item = widget.items[i];
                      final tl = _meterToPixel(item.xM, item.zM);
                      final w = item.effectiveW * _pixelScale;
                      final h = item.effectiveD * _pixelScale;
                      return Positioned(
                        left: tl.dx,
                        top: tl.dy,
                        width: w,
                        height: h,
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedIdx = _selectedIdx == i ? -1 : i),
                          onPanUpdate: (details) {
                            setState(() {
                              _selectedIdx = i;
                              final newX = item.xM + details.delta.dx / _pixelScale;
                              final newZ = item.zM + details.delta.dy / _pixelScale;
                              item.xM = newX.clamp(0, widget.roomWidthM - item.effectiveW);
                              item.zM = newZ.clamp(0, widget.roomLengthM - item.effectiveD);
                            });
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: widget.colors[i % widget.colors.length].withAlpha(_selectedIdx == i ? 180 : 120),
                              border: Border.all(
                                color: _selectedIdx == i ? Colors.white : Colors.white54,
                                width: _selectedIdx == i ? 2.5 : 1,
                              ),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            alignment: Alignment.center,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: Text(
                                  item.product.name.length > 14
                                      ? '${item.product.name.substring(0, 14)}…'
                                      : item.product.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            _buildBottomBar(),
          ],
        );
      }),
    );
  }

  Widget _buildBottomBar() {
    if (_selectedIdx < 0 || _selectedIdx >= widget.items.length) {
      return Container(
        height: 80,
        padding: const EdgeInsets.all(16),
        color: const Color(0xFF16213E),
        child: const Center(
          child: Text('Tap a furniture item to select, then drag to reposition',
              style: TextStyle(color: Colors.white54, fontSize: 13)),
        ),
      );
    }
    final item = widget.items[_selectedIdx];
    final color = widget.colors[_selectedIdx % widget.colors.length];
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF16213E),
      child: Row(
        children: [
          CircleAvatar(backgroundColor: color, radius: 16,
            child: const Icon(Icons.drag_indicator, color: Colors.white, size: 18)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(item.product.name,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                Text(
                  '${DimensionFormatter.format(item.effectiveW)} × '
                  '${DimensionFormatter.format(item.effectiveD)}'
                  '${item.isFloorItem ? '  (floor item — can overlap)' : ''}',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.rotate_right, color: Colors.white70),
            tooltip: 'Rotate 90°',
            onPressed: () {
              setState(() {
                item.rotationY = (item.rotationY + 90) % 360;
                item.xM = item.xM.clamp(0, widget.roomWidthM - item.effectiveW);
                item.zM = item.zM.clamp(0, widget.roomLengthM - item.effectiveD);
              });
            },
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Painters
// ═════════════════════════════════════════════════════════════════════════════

class _LayoutPreviewPainter extends CustomPainter {
  final double roomWidthM;
  final double roomLengthM;
  final List<_PlacedItem> items;
  final List<Color> colors;

  _LayoutPreviewPainter({
    required this.roomWidthM,
    required this.roomLengthM,
    required this.items,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const padding = 40.0;
    final aw = size.width - padding * 2;
    final ah = size.height - padding * 2;
    final sx = aw / roomWidthM;
    final sz = ah / roomLengthM;
    final scale = math.min(sx, sz);
    final rw = roomWidthM * scale;
    final rh = roomLengthM * scale;
    final ox = padding + (aw - rw) / 2;
    final oz = padding + (ah - rh) / 2;

    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(ox, oz, rw, rh), const Radius.circular(4)),
      Paint()..color = const Color(0xFFE8E8E8),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(ox, oz, rw, rh), const Radius.circular(4)),
      Paint()..color = Colors.grey..style = PaintingStyle.stroke..strokeWidth = 1.5,
    );

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final color = colors[i % colors.length];
      final x = ox + item.xM * scale;
      final z = oz + item.zM * scale;
      final w = item.effectiveW * scale;
      final h = item.effectiveD * scale;

      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, z, w, h), const Radius.circular(2)),
        Paint()..color = color.withAlpha(item.isFloorItem ? 80 : 180),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, z, w, h), const Radius.circular(2)),
        Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 1.5,
      );

      final tp = TextPainter(
        text: TextSpan(
          text: item.product.name.length > 10 ? '${item.product.name.substring(0, 10)}…' : item.product.name,
          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: w - 4);
      if (tp.width <= w - 4 && tp.height <= h - 4) {
        tp.paint(canvas, Offset(x + (w - tp.width) / 2, z + (h - tp.height) / 2));
      }
    }

    const cs = TextStyle(color: Colors.black54, fontSize: 12, fontWeight: FontWeight.bold);
    _drawText(canvas, 'N', ox + rw / 2 - 6, oz - 18, cs);
    _drawText(canvas, 'S', ox + rw / 2 - 6, oz + rh + 4, cs);
    _drawText(canvas, 'W', ox - 20, oz + rh / 2 - 6, cs);
    _drawText(canvas, 'E', ox + rw + 6, oz + rh / 2 - 6, cs);
  }

  void _drawText(Canvas canvas, String text, double x, double y, TextStyle style) {
    final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, Offset(x, y));
  }

  @override
  bool shouldRepaint(covariant _LayoutPreviewPainter old) => true;
}

class _InteractivePainter extends CustomPainter {
  final double roomWidthM;
  final double roomLengthM;
  final List<_PlacedItem> items;
  final List<Color> colors;
  final int selectedIdx;
  final double scale;

  _InteractivePainter({
    required this.roomWidthM,
    required this.roomLengthM,
    required this.items,
    required this.colors,
    required this.selectedIdx,
    required this.scale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 48.0;
    final aw = size.width - pad * 2;
    final ah = size.height - pad * 2;
    final sx = aw / roomWidthM;
    final sz = ah / roomLengthM;
    final ps = math.min(sx, sz);
    final rw = roomWidthM * ps;
    final rh = roomLengthM * ps;
    final ox = pad + (aw - rw) / 2;
    final oz = pad + (ah - rh) / 2;

    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(ox, oz, rw, rh), const Radius.circular(4)),
      Paint()..color = const Color(0xFF2D3460),
    );

    final gridPaint = Paint()..color = Colors.white10..strokeWidth = 0.5;
    final meterPx = ps;
    for (double x = ox; x <= ox + rw; x += meterPx) {
      canvas.drawLine(Offset(x, oz), Offset(x, oz + rh), gridPaint);
    }
    for (double z = oz; z <= oz + rh; z += meterPx) {
      canvas.drawLine(Offset(ox, z), Offset(ox + rw, z), gridPaint);
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(ox, oz, rw, rh), const Radius.circular(4)),
      Paint()..color = Colors.white30..style = PaintingStyle.stroke..strokeWidth = 2,
    );

    const cs = TextStyle(color: Colors.white38, fontSize: 14, fontWeight: FontWeight.bold);
    _drawText(canvas, 'N', ox + rw / 2 - 6, oz - 24, cs);
    _drawText(canvas, 'S', ox + rw / 2 - 6, oz + rh + 8, cs);
    _drawText(canvas, 'W', ox - 22, oz + rh / 2 - 7, cs);
    _drawText(canvas, 'E', ox + rw + 8, oz + rh / 2 - 7, cs);

    final dimStyle = TextStyle(color: Colors.white24, fontSize: 10);
    _drawText(canvas, '${roomWidthM.toStringAsFixed(1)}m', ox + rw / 2 - 15, oz + rh + 22, dimStyle);
    _drawText(canvas, '${roomLengthM.toStringAsFixed(1)}m', ox + rw + 20, oz + rh / 2 - 5, dimStyle);
  }

  void _drawText(Canvas canvas, String text, double x, double y, TextStyle style) {
    final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, Offset(x, y));
  }

  @override
  bool shouldRepaint(covariant _InteractivePainter old) => true;
}

class _ProductCard extends StatelessWidget {
  final ProductModel product;
  final VoidCallback onTap;

  const _ProductCard({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 120,
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: product.imageUrl != null && product.imageUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: product.imageUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                        errorWidget: (_, __, ___) => const Icon(Icons.image_not_supported, size: 40),
                      )
                    : const Center(child: Icon(Icons.chair, size: 40, color: Colors.grey)),
              ),
              Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall),
                    Text('₹${(product.priceUsd * 83.5).round()}',
                        style: Theme.of(context).textTheme.labelMedium),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
