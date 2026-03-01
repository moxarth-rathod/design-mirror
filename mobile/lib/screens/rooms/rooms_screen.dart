/// DesignMirror AI — Rooms Screen
///
/// Dedicated screen for managing user's rooms. Supports viewing,
/// deleting, and navigating to furniture catalog for each room.

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../config/units.dart';
import '../../models/room_model.dart';
import '../../repositories/room_repository.dart';
import '../../widgets/room_dimension_view.dart';

class RoomsScreen extends StatefulWidget {
  const RoomsScreen({super.key});

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  List<RoomModel>? _rooms;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRooms();
  }

  Future<void> _loadRooms() async {
    setState(() { _loading = true; _error = null; });
    try {
      final repo = GetIt.instance<RoomRepository>();
      final rooms = await repo.getUserRooms();
      if (mounted) setState(() { _rooms = rooms; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _deleteRoom(String roomId) async {
    try {
      final repo = GetIt.instance<RoomRepository>();
      await repo.deleteRoom(roomId);
      _loadRooms();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Rooms'),
        actions: const [],
      ),
      body: RefreshIndicator(
        onRefresh: _loadRooms,
        child: _buildBody(),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddRoomChoice,
        backgroundColor: AppTheme.accent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Room'),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(48),
            child: Column(
              children: [
                Icon(Icons.error_outline, size: 48, color: AppTheme.error),
                const SizedBox(height: 8),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                TextButton(onPressed: _loadRooms, child: const Text('Retry')),
              ],
            ),
          ),
        ],
      );
    }

    if (_rooms == null || _rooms!.isEmpty) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 32),
            child: Column(
              children: [
                Icon(Icons.meeting_room_outlined,
                    size: 72, color: AppTheme.mutedOf(context).withAlpha(100)),
                const SizedBox(height: 20),
                Text('No rooms yet',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: AppTheme.mutedOf(context))),
                const SizedBox(height: 8),
                Text(
                  'Add a room to start checking furniture fit.\nUse the button below or AR scan above.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppTheme.secondaryTextOf(context), fontSize: 13, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
      itemCount: _rooms!.length,
      itemBuilder: (_, i) => _buildRoomCard(_rooms![i]),
    );
  }

  Widget _buildRoomCard(RoomModel room) {
    final dims = room.dimensions;
    final widthM = dims?['width_m'] as num?;
    final lengthM = dims?['length_m'] as num?;
    final heightM = dims?['height_m'] as num?;
    final areaM2 = dims?['area_m2'] as num?;
    final source = dims?['source'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push(
          '${AppRoutes.catalog}?room_id=${room.id}'
              '&room_name=${Uri.encodeComponent(room.roomName)}'
              '&width=${widthM ?? 0}'
              '&length=${lengthM ?? 0}'
              '&height=${heightM ?? 0}',
        ),
        onLongPress: widthM != null && lengthM != null
            ? () => _showRoomDetails(room, widthM, lengthM, heightM, areaM2)
            : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.meeting_room_outlined,
                    color: AppTheme.primary, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(room.roomName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 15)),
                        ),
                        if (room.roomType != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            margin: const EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withAlpha(25),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _formatRoomType(room.roomType!),
                              style: TextStyle(fontSize: 10, color: AppTheme.primary),
                            ),
                          ),
                        if (source != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: (source == 'manual'
                                      ? AppTheme.success
                                      : AppTheme.accent)
                                  .withAlpha(30),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                                source == 'manual' ? 'Manual' : 'AR Scan',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: source == 'manual'
                                        ? AppTheme.success
                                        : AppTheme.accent)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (widthM != null && lengthM != null)
                      Text(
                        '${DimensionFormatter.format(widthM.toDouble())} × ${DimensionFormatter.format(lengthM.toDouble())}'
                        '${heightM != null ? ' × ${DimensionFormatter.format(heightM.toDouble())}' : ''}'
                        '${areaM2 != null ? '  ·  ${areaM2.toStringAsFixed(1)} m²' : ''}',
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.secondaryTextOf(context)),
                      )
                    else
                      Text(room.status,
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.secondaryTextOf(context))),
                    const SizedBox(height: 2),
                    Text('Long press for 3D view  ·  Tap to browse furniture',
                        style: TextStyle(
                            fontSize: 10,
                            color: AppTheme.secondaryTextOf(context).withAlpha(120))),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline,
                    size: 20, color: AppTheme.error.withAlpha(150)),
                onPressed: () => _confirmDeleteRoom(room),
              ),
              Icon(Icons.arrow_forward_ios,
                  size: 14, color: AppTheme.secondaryTextOf(context)),
            ],
          ),
        ),
      ),
    );
  }

  void _showRoomDetails(
      RoomModel room, num widthM, num lengthM, num? heightM, num? areaM2) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        builder: (ctx2, controller) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: _RoomDetailContent(
            room: room,
            widthM: widthM,
            lengthM: lengthM,
            heightM: heightM,
            areaM2: areaM2,
            scrollController: controller,
            onRefresh: _loadRooms,
          ),
        ),
      ),
    );
  }

  void _showAddRoomChoice() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withAlpha(60),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text('How do you want to add a room?',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 20),
              _addRoomOption(
                icon: Icons.edit_outlined,
                color: AppTheme.primary,
                title: 'Manual Entry',
                subtitle: 'Type in width, length, and height',
                onTap: () async {
                  Navigator.pop(ctx);
                  await context.push(AppRoutes.manualRoom);
                  _loadRooms();
                },
              ),
              const SizedBox(height: 12),
              _addRoomOption(
                icon: Icons.view_in_ar_rounded,
                color: AppTheme.accent,
                title: 'AR Scan',
                subtitle: 'Measure your room using the camera',
                onTap: () async {
                  Navigator.pop(ctx);
                  await context.push(AppRoutes.arScanner);
                  _loadRooms();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addRoomOption({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withAlpha(40)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withAlpha(20),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 13, color: AppTheme.secondaryTextOf(context))),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios,
                size: 14, color: AppTheme.secondaryTextOf(context)),
          ],
        ),
      ),
    );
  }

  String _formatRoomType(String type) {
    return type.split('_').map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
  }

  void _confirmDeleteRoom(RoomModel room) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Room'),
        content: Text('Delete "${room.roomName}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteRoom(room.id);
            },
            child: Text('Delete', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
  }
}

/// Stateful content for the room detail bottom sheet — manages photos.
class _RoomDetailContent extends StatefulWidget {
  final RoomModel room;
  final num widthM, lengthM;
  final num? heightM, areaM2;
  final ScrollController scrollController;
  final VoidCallback onRefresh;

  const _RoomDetailContent({
    required this.room,
    required this.widthM,
    required this.lengthM,
    this.heightM,
    this.areaM2,
    required this.scrollController,
    required this.onRefresh,
  });

  @override
  State<_RoomDetailContent> createState() => _RoomDetailContentState();
}

class _RoomDetailContentState extends State<_RoomDetailContent> {
  final _roomRepo = GetIt.instance<RoomRepository>();
  late List<String> _photos;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _photos = List.from(widget.room.photos);
  }

  Future<void> _addPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    setState(() => _uploading = true);
    try {
      final result =
          await _roomRepo.uploadPhoto(widget.room.id, picked.path);
      final photos = (result['photos'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [];
      setState(() => _photos = photos);
      widget.onRefresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    }
    if (mounted) setState(() => _uploading = false);
  }

  Future<void> _deletePhoto(int index) async {
    final removed = _photos.removeAt(index);
    setState(() {});
    try {
      await _roomRepo.deletePhoto(widget.room.id, index);
      widget.onRefresh();
    } catch (_) {
      _photos.insert(index, removed);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(24),
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
        Text(widget.room.roomName,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        RoomDimensionView(
          widthM: widget.widthM.toDouble(),
          lengthM: widget.lengthM.toDouble(),
          heightM: (widget.heightM ?? 2.5).toDouble(),
          size: 200,
        ),
        const SizedBox(height: 16),
        if (widget.areaM2 != null)
          Text(
            'Floor Area: ${widget.areaM2!.toStringAsFixed(1)} m²'
            '  ·  Dimensions: '
            '${DimensionFormatter.format(widget.widthM.toDouble())} × '
            '${DimensionFormatter.format(widget.lengthM.toDouble())}',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 14,
                color: AppTheme.secondaryTextOf(context),
                height: 1.5),
          ),
        const SizedBox(height: 24),

        // ── Photos Section ───────────────────
        Row(
          children: [
            const Text('Reference Photos',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            const Spacer(),
            if (_uploading)
              const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else
              IconButton(
                icon: const Icon(Icons.add_a_photo_outlined, size: 22),
                onPressed: _addPhoto,
                tooltip: 'Add Photo',
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_photos.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            alignment: Alignment.center,
            child: Text(
              'No photos yet. Tap + to add reference photos.',
              style: TextStyle(
                  fontSize: 13, color: AppTheme.mutedOf(context)),
            ),
          )
        else
          SizedBox(
            height: 100,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _photos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _buildPhotoThumb(i),
            ),
          ),
        const SizedBox(height: 20),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              context.push(
                '${AppRoutes.catalog}?room_id=${widget.room.id}'
                '&room_name=${Uri.encodeComponent(widget.room.roomName)}'
                '&width=${widget.widthM}&length=${widget.lengthM}'
                '&height=${widget.heightM ?? 0}',
              );
            },
            child: const Text('Browse Furniture for This Room'),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  context.push(
                    '${AppRoutes.recommendations}'
                    '?roomId=${widget.room.id}'
                    '&roomName=${Uri.encodeComponent(widget.room.roomName)}'
                    '&roomType=${widget.room.roomType ?? ''}',
                  );
                },
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('Recommendations'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  context.push(
                    '${AppRoutes.layoutPlanner}'
                    '?roomId=${widget.room.id}'
                    '&roomName=${Uri.encodeComponent(widget.room.roomName)}',
                  );
                },
                icon: const Icon(Icons.dashboard_customize, size: 18),
                label: const Text('Layout Plan'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildPhotoThumb(int index) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: CachedNetworkImage(
            imageUrl: _photos[index],
            width: 100,
            height: 100,
            fit: BoxFit.cover,
            placeholder: (_, __) =>
                Container(width: 100, height: 100, color: AppTheme.surfaceDimOf(context)),
            errorWidget: (_, __, ___) => Container(
              width: 100,
              height: 100,
              color: AppTheme.surfaceDimOf(context),
              child: Icon(Icons.broken_image, color: AppTheme.mutedOf(context)),
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: () => _deletePhoto(index),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
