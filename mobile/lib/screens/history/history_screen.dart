/// DesignMirror AI — Design History Screen

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';

import '../../config/theme.dart';
import '../../services/api_service.dart';
import '../../widgets/room_dimension_view.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _api = GetIt.instance<ApiService>();
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
      final res = await _api.get('/fitcheck/history?page=1&page_size=50');
      final data = res.data as Map<String, dynamic>;
      _items = (data['items'] as List<dynamic>)
          .map((e) => e as Map<String, dynamic>)
          .toList();
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _delete(String id, int index) async {
    final removed = _items.removeAt(index);
    setState(() {});
    try {
      await _api.delete('/fitcheck/history/$id');
    } catch (_) {
      _items.insert(index, removed);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Design History')),
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
          Icon(Icons.history_rounded,
              size: 64, color: AppTheme.mutedOf(context)),
          const SizedBox(height: 16),
          Text('No fit-check history yet',
              style: TextStyle(
                  fontSize: 18, color: AppTheme.secondaryTextOf(context))),
          const SizedBox(height: 8),
          Text('Run a fit-check from the catalog to see results here.',
              style: TextStyle(
                  fontSize: 13, color: AppTheme.mutedOf(context))),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context, int index) {
    final item = _items[index];
    final verdict = item['verdict'] as String? ?? '';
    final score = item['design_score'] as int? ?? 0;
    final date = DateTime.tryParse(item['created_at'] as String? ?? '');
    final dateStr = date != null
        ? DateFormat('MMM d, yyyy – h:mm a').format(date.toLocal())
        : '';

    Color badgeColor;
    String badgeLabel;
    if (verdict == 'fits') {
      badgeColor = AppTheme.success;
      badgeLabel = 'Fits';
    } else if (verdict == 'tight_fit') {
      badgeColor = AppTheme.accent;
      badgeLabel = 'Tight';
    } else {
      badgeColor = AppTheme.error;
      badgeLabel = 'Too Large';
    }

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
      onDismissed: (_) => _delete(item['id'] as String, index),
      child: GestureDetector(
        onTap: () => _showDetail(item),
        child: Container(
          padding: const EdgeInsets.all(16),
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
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  verdict == 'fits'
                      ? Icons.check_circle_outline
                      : verdict == 'tight_fit'
                          ? Icons.warning_amber_rounded
                          : Icons.cancel_outlined,
                  color: badgeColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['product_name'] as String? ?? '',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${item['room_name'] ?? ''}  •  Score $score/100',
                      style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.secondaryTextOf(context)),
                    ),
                    if (dateStr.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        dateStr,
                        style: TextStyle(
                            fontSize: 11, color: AppTheme.mutedOf(context)),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badgeLabel,
                  style: TextStyle(
                    color: badgeColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(Map<String, dynamic> item) {
    final snapshot = item['result_snapshot'] as Map<String, dynamic>? ?? {};
    final clearance = snapshot['clearance'] as Map<String, dynamic>? ?? {};
    final fillPct = (snapshot['room_fill_percent'] as num?)?.toDouble() ?? 0;
    final suggestion = snapshot['suggestion'] as String? ?? '';
    final verdict = snapshot['verdict'] as String? ?? '';
    final score = (snapshot['design_score'] as num?)?.toInt() ?? 0;

    final roomDims = snapshot['room_dimensions'] as Map<String, dynamic>?;
    final placement = snapshot['placement_used'] as Map<String, dynamic>?;
    final footprint = snapshot['furniture_footprint'] as Map<String, dynamic>?;

    final roomW = (roomDims?['width_m'] as num?)?.toDouble() ?? 3.0;
    final roomL = (roomDims?['length_m'] as num?)?.toDouble() ?? 3.0;
    final roomH = (roomDims?['height_m'] as num?)?.toDouble() ?? 2.5;

    final fW = (footprint?['width_m'] as num?)?.toDouble() ?? 0.5;
    final fD = (footprint?['depth_m'] as num?)?.toDouble() ?? 0.5;
    // Approximate furniture height from room height ratio
    final fH = roomH * 0.4;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        minChildSize: 0.3,
        builder: (ctx, controller) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.all(20),
            children: [
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
              Text(
                '${item['product_name']}  →  ${item['room_name']}',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
              ),
              const SizedBox(height: 12),
              _chip(
                verdict == 'fits'
                    ? 'Fits'
                    : verdict == 'tight_fit'
                        ? 'Tight Fit'
                        : 'Too Large',
                verdict == 'fits'
                    ? AppTheme.success
                    : verdict == 'tight_fit'
                        ? AppTheme.accent
                        : AppTheme.error,
              ),
              const SizedBox(height: 8),
              Text('Design Score: $score / 100'),
              Text('Floor Coverage: ${fillPct.toStringAsFixed(1)}%'),
              const SizedBox(height: 16),

              // ── Furniture vs Room Diagram ─────
              if (roomDims != null) ...[
                const Text('Furniture vs. Room',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Center(
                  child: FurnitureInRoomView(
                    roomWidthM: roomW,
                    roomLengthM: roomL,
                    roomHeightM: roomH,
                    furnitureWidthM: fW,
                    furnitureLengthM: fD,
                    furnitureHeightM: fH,
                    size: 240,
                    placementX: (placement?['x'] as num?)?.toDouble(),
                    placementZ: (placement?['z'] as num?)?.toDouble(),
                    placementRotation:
                        (placement?['rotation_y'] as num?)?.toDouble(),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              if (clearance.isNotEmpty) ...[
                const Text('Clearance',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 12,
                  children: clearance.entries.map((e) {
                    final val = (e.value as num?)?.toDouble() ?? 0;
                    return Chip(
                      label: Text(
                          '${e.key.toUpperCase()}: ${val.toStringAsFixed(2)}m'),
                      backgroundColor: AppTheme.surfaceDimOf(context),
                    );
                  }).toList(),
                ),
              ],
              if (suggestion.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Suggestion',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceDimOf(context),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(suggestion, style: const TextStyle(fontSize: 13)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w600, fontSize: 13)),
      ),
    );
  }
}
