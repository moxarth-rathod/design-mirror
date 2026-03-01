/// DesignMirror AI — Manual Room Input Screen
///
/// Lets users enter room dimensions manually (width, length, height)
/// instead of using AR scanning. Works as a practical alternative
/// until ARCore integration is complete.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../repositories/room_repository.dart';

class ManualRoomScreen extends StatefulWidget {
  const ManualRoomScreen({super.key});

  @override
  State<ManualRoomScreen> createState() => _ManualRoomScreenState();
}

class _ManualRoomScreenState extends State<ManualRoomScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController(text: 'Living Room');
  final _widthController = TextEditingController();
  final _lengthController = TextEditingController();
  final _heightController = TextEditingController();

  String? _selectedRoomType;
  bool _useFeet = false;
  bool _isSubmitting = false;

  static const _roomTypes = {
    'bedroom': ('Bedroom', Icons.bed_outlined),
    'living_room': ('Living Room', Icons.weekend_outlined),
    'dining_room': ('Dining Room', Icons.dining_outlined),
    'office': ('Office', Icons.desk_outlined),
    'kitchen': ('Kitchen', Icons.kitchen_outlined),
    'bathroom': ('Bathroom', Icons.bathtub_outlined),
    'kids_room': ('Kids Room', Icons.child_care_outlined),
    'guest_room': ('Guest Room', Icons.single_bed_outlined),
    'other': ('Other', Icons.other_houses_outlined),
  };

  @override
  void dispose() {
    _nameController.dispose();
    _widthController.dispose();
    _lengthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  double _toMeters(String value) {
    final v = double.tryParse(value) ?? 0;
    return _useFeet ? v * 0.3048 : v;
  }

  String get _unitLabel => _useFeet ? 'ft' : 'm';

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final repo = GetIt.instance<RoomRepository>();
      final room = await repo.createManualRoom(
        roomName: _nameController.text.trim(),
        widthM: _toMeters(_widthController.text),
        lengthM: _toMeters(_lengthController.text),
        heightM: _heightController.text.isNotEmpty
            ? _toMeters(_heightController.text)
            : null,
        roomType: _selectedRoomType,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Room "${room.roomName}" created successfully!'),
          backgroundColor: AppTheme.success,
        ),
      );

      context.go(AppRoutes.home);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Room'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Info Card ────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.accent.withAlpha(60)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.straighten, color: AppTheme.accent, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Measure your room with a tape measure and enter '
                        'the width and length below.',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.secondaryTextOf(context),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── Room Name ────────────────────────
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Room Name',
                  prefixIcon: Icon(Icons.meeting_room_outlined),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter a room name' : null,
              ),
              const SizedBox(height: 16),

              // ── Room Type ─────────────────────────
              DropdownButtonFormField<String>(
                value: _selectedRoomType,
                decoration: const InputDecoration(
                  labelText: 'Room Type (for recommendations)',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                items: _roomTypes.entries.map((e) {
                  return DropdownMenuItem(
                    value: e.key,
                    child: Row(
                      children: [
                        Icon(e.value.$2, size: 20),
                        const SizedBox(width: 10),
                        Text(e.value.$1),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (v) => setState(() => _selectedRoomType = v),
              ),
              const SizedBox(height: 20),

              // ── Unit Toggle ──────────────────────
              Row(
                children: [
                  Text(
                    'Unit:',
                    style: TextStyle(
                      color: AppTheme.secondaryTextOf(context),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 12),
                  ChoiceChip(
                    label: const Text('Meters'),
                    selected: !_useFeet,
                    onSelected: (_) => setState(() => _useFeet = false),
                    selectedColor: AppTheme.accent.withAlpha(40),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Feet'),
                    selected: _useFeet,
                    onSelected: (_) => setState(() => _useFeet = true),
                    selectedColor: AppTheme.accent.withAlpha(40),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Room Diagram ─────────────────────
              _buildRoomDiagram(),
              const SizedBox(height: 20),

              // ── Width Input ──────────────────────
              TextFormField(
                controller: _widthController,
                decoration: InputDecoration(
                  labelText: 'Width ($_unitLabel)',
                  prefixIcon: const Icon(Icons.swap_horiz),
                  hintText: _useFeet ? 'e.g. 12' : 'e.g. 3.5',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                ],
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Enter width';
                  final n = double.tryParse(v);
                  if (n == null || n <= 0) return 'Enter a valid number';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // ── Length Input ─────────────────────
              TextFormField(
                controller: _lengthController,
                decoration: InputDecoration(
                  labelText: 'Length ($_unitLabel)',
                  prefixIcon: const Icon(Icons.swap_vert),
                  hintText: _useFeet ? 'e.g. 15' : 'e.g. 4.5',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                ],
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Enter length';
                  final n = double.tryParse(v);
                  if (n == null || n <= 0) return 'Enter a valid number';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // ── Height Input (optional) ──────────
              TextFormField(
                controller: _heightController,
                decoration: InputDecoration(
                  labelText: 'Ceiling Height ($_unitLabel) — optional',
                  prefixIcon: const Icon(Icons.height),
                  hintText: _useFeet ? 'e.g. 9' : 'e.g. 2.7',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                ],
                validator: (v) {
                  if (v == null || v.isEmpty) return null;
                  final n = double.tryParse(v);
                  if (n == null || n <= 0) return 'Enter a valid number';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // ── Computed Area Preview ────────────
              _buildAreaPreview(),
              const SizedBox(height: 32),

              // ── Submit Button ────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isSubmitting ? null : _submit,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check),
                  label: Text(_isSubmitting ? 'Creating...' : 'Create Room'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.success,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoomDiagram() {
    final w = double.tryParse(_widthController.text) ?? 0;
    final l = double.tryParse(_lengthController.text) ?? 0;
    final hasValues = w > 0 && l > 0;

    return Container(
      height: 160,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.surfaceDimOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: CustomPaint(
        painter: _RoomDiagramPainter(
          width: w,
          length: l,
          unit: _unitLabel,
          hasValues: hasValues,
        ),
      ),
    );
  }

  Widget _buildAreaPreview() {
    final w = double.tryParse(_widthController.text);
    final l = double.tryParse(_lengthController.text);

    if (w == null || l == null || w <= 0 || l <= 0) {
      return const SizedBox.shrink();
    }

    final wM = _useFeet ? w * 0.3048 : w;
    final lM = _useFeet ? l * 0.3048 : l;
    final areaM2 = wM * lM;
    final areaFt2 = areaM2 * 10.7639;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.success.withAlpha(20),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.crop_square, size: 18, color: AppTheme.success),
          const SizedBox(width: 8),
          Text(
            'Floor area: ${areaM2.toStringAsFixed(1)} m²  (${areaFt2.toStringAsFixed(0)} ft²)',
            style: TextStyle(
              color: AppTheme.success,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomDiagramPainter extends CustomPainter {
  final double width;
  final double length;
  final String unit;
  final bool hasValues;

  _RoomDiagramPainter({
    required this.width,
    required this.length,
    required this.unit,
    required this.hasValues,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    if (!hasValues) {
      final tp = TextPainter(
        text: const TextSpan(
          text: 'Enter dimensions to preview',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
      return;
    }

    final maxDim = width > length ? width : length;
    final scale = (size.width * 0.55) / maxDim;
    final rw = width * scale;
    final rl = length * scale;

    final roomRect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: rw,
      height: rl,
    );

    // Room fill
    final fillPaint = Paint()
      ..color = const Color(0xFFE17055).withAlpha(20)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(roomRect, const Radius.circular(4)),
      fillPaint,
    );

    // Room outline
    final outlinePaint = Paint()
      ..color = const Color(0xFFE17055)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(
      RRect.fromRectAndRadius(roomRect, const Radius.circular(4)),
      outlinePaint,
    );

    // Width label (top)
    _drawLabel(
      canvas,
      '${width.toStringAsFixed(1)} $unit',
      Offset(cx, roomRect.top - 14),
      const Color(0xFF2D3436),
    );

    // Length label (right)
    _drawLabel(
      canvas,
      '${length.toStringAsFixed(1)} $unit',
      Offset(roomRect.right + 8, cy),
      const Color(0xFF2D3436),
    );

    // Corner dots
    final dotPaint = Paint()
      ..color = const Color(0xFFE17055)
      ..style = PaintingStyle.fill;
    final corners = [
      roomRect.topLeft,
      roomRect.topRight,
      roomRect.bottomRight,
      roomRect.bottomLeft,
    ];
    for (final c in corners) {
      canvas.drawCircle(c, 4, dotPaint);
    }
  }

  void _drawLabel(Canvas canvas, String text, Offset pos, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _RoomDiagramPainter old) =>
      old.width != width || old.length != length || old.unit != unit;
}
