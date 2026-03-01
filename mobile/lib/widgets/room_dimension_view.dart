/// DesignMirror AI — 3D Dimension Visualization
///
/// Clean isometric rendering of room + furniture for fit-check results.
/// Compact view: visual only — no clutter.  Fullscreen: labeled + zoomable.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../config/units.dart';

// ═══════════════════════════════════════════════
// PUBLIC WIDGET: Single object dimensions
// ═══════════════════════════════════════════════

class RoomDimensionView extends StatelessWidget {
  final double widthM;
  final double lengthM;
  final double heightM;
  final double size;
  final Color lineColor;
  final Color bgColor;

  const RoomDimensionView({
    super.key,
    required this.widthM,
    required this.lengthM,
    required this.heightM,
    this.size = 180,
    this.lineColor = Colors.white,
    this.bgColor = const Color(0xFF1A1A2E),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: CustomPaint(
        painter: _SingleBlockPainter(
          widthM: widthM,
          lengthM: lengthM,
          heightM: heightM,
          blockColor: const Color(0xFF42A5F5),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// PUBLIC WIDGET: Furniture inside room comparison
// ═══════════════════════════════════════════════

class FurnitureInRoomView extends StatefulWidget {
  final double roomWidthM;
  final double roomLengthM;
  final double roomHeightM;
  final double furnitureWidthM;
  final double furnitureLengthM;
  final double furnitureHeightM;
  final double size;

  final double? placementX;
  final double? placementZ;
  final double? placementRotation;

  const FurnitureInRoomView({
    super.key,
    required this.roomWidthM,
    required this.roomLengthM,
    required this.roomHeightM,
    required this.furnitureWidthM,
    required this.furnitureLengthM,
    required this.furnitureHeightM,
    this.size = 260,
    this.placementX,
    this.placementZ,
    this.placementRotation,
  });

  @override
  State<FurnitureInRoomView> createState() => _FurnitureInRoomViewState();
}

class _FurnitureInRoomViewState extends State<FurnitureInRoomView> {
  @override
  Widget build(BuildContext context) {
    final fillPercent = (widget.furnitureWidthM * widget.furnitureLengthM) /
        (widget.roomWidthM * widget.roomLengthM) *
        100;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Diagram
        Stack(
          children: [
            Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: CustomPaint(
                painter: _ComparisonChartPainter(
                  roomW: widget.roomWidthM,
                  roomL: widget.roomLengthM,
                  roomH: widget.roomHeightM,
                  furW: widget.furnitureWidthM,
                  furL: widget.furnitureLengthM,
                  furH: widget.furnitureHeightM,
                  placementX: widget.placementX,
                  placementZ: widget.placementZ,
                  placementRotation: widget.placementRotation,
                  showLabels: false,
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () => _openFullscreen(context),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.fullscreen,
                      size: 20, color: Colors.white70),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Compact info strip
        Container(
          width: widget.size,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.surfaceDimOf(context),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  _infoBox(
                    _kColorRoom,
                    'Room',
                    DimensionFormatter.formatCompact(
                        widget.roomWidthM, widget.roomLengthM, widget.roomHeightM),
                  ),
                  const SizedBox(width: 8),
                  _infoBox(
                    _kColorFurniture,
                    'Furniture',
                    DimensionFormatter.formatCompact(
                        widget.furnitureWidthM, widget.furnitureLengthM,
                        widget.furnitureHeightM),
                  ),
                  const SizedBox(width: 8),
                  _fillBadge(fillPercent),
                ],
              ),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () => _openFullscreen(context),
                child: Text(
                  'Tap diagram to expand',
                  style: TextStyle(fontSize: 9, color: AppTheme.secondaryTextOf(context)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _infoBox(Color color, String label, String dims) {
    return Expanded(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 9,
                        color: AppTheme.secondaryTextOf(context),
                        fontWeight: FontWeight.w600)),
                Text(dims,
                    style: const TextStyle(
                        fontSize: 9.5, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fillBadge(double percent) {
    final color = percent > 60
        ? AppTheme.error
        : percent > 40
            ? Colors.orange
            : AppTheme.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '${percent.toStringAsFixed(0)}%',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  void _openFullscreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FullscreenDiagram(
          roomW: widget.roomWidthM,
          roomL: widget.roomLengthM,
          roomH: widget.roomHeightM,
          furW: widget.furnitureWidthM,
          furL: widget.furnitureLengthM,
          furH: widget.furnitureHeightM,
          placementX: widget.placementX,
          placementZ: widget.placementZ,
          placementRotation: widget.placementRotation,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// FULLSCREEN DIAGRAM VIEW
// ═══════════════════════════════════════════════

class _FullscreenDiagram extends StatefulWidget {
  final double roomW, roomL, roomH;
  final double furW, furL, furH;
  final double? placementX, placementZ, placementRotation;

  const _FullscreenDiagram({
    required this.roomW,
    required this.roomL,
    required this.roomH,
    required this.furW,
    required this.furL,
    required this.furH,
    this.placementX,
    this.placementZ,
    this.placementRotation,
  });

  @override
  State<_FullscreenDiagram> createState() => _FullscreenDiagramState();
}

class _FullscreenDiagramState extends State<_FullscreenDiagram> {
  double _zoom = 1.0;
  double _baseZoom = 1.0;
  Offset _pan = Offset.zero;
  Offset _basePan = Offset.zero;

  void _zoomIn() => setState(() => _zoom = (_zoom + 0.3).clamp(0.5, 5.0));
  void _zoomOut() => setState(() => _zoom = (_zoom - 0.3).clamp(0.5, 5.0));
  void _resetView() => setState(() { _zoom = 1.0; _pan = Offset.zero; });

  @override
  Widget build(BuildContext context) {
    final fillPercent = (widget.furW * widget.furL) /
        (widget.roomW * widget.roomL) *
        100;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Furniture vs. Room'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            tooltip: 'Zoom Out',
            onPressed: _zoomOut,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Center(
              child: Text(
                '${(_zoom * 100).round()}%',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Zoom In',
            onPressed: _zoomIn,
          ),
          IconButton(
            icon: const Icon(Icons.restart_alt),
            tooltip: 'Reset View',
            onPressed: _resetView,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onScaleStart: (d) {
                _baseZoom = _zoom;
                _basePan = _pan;
              },
              onScaleUpdate: (d) {
                setState(() {
                  _zoom = (_baseZoom * d.scale).clamp(0.5, 5.0);
                  if (d.pointerCount == 1) {
                    _pan = _basePan + d.focalPointDelta;
                  }
                });
              },
              onDoubleTap: _resetView,
              child: ClipRect(
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..translate(_pan.dx, _pan.dy)
                    ..scale(_zoom),
                  child: SizedBox.expand(
                    child: CustomPaint(
                      painter: _ComparisonChartPainter(
                        roomW: widget.roomW,
                        roomL: widget.roomL,
                        roomH: widget.roomH,
                        furW: widget.furW,
                        furL: widget.furL,
                        furH: widget.furH,
                        placementX: widget.placementX,
                        placementZ: widget.placementZ,
                        placementRotation: widget.placementRotation,
                        showLabels: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Bottom info bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: const Color(0xFF1A1A2E),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Compass color legend
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _compassChip('N', _kColorN),
                      const SizedBox(width: 12),
                      _compassChip('S', _kColorS),
                      const SizedBox(width: 12),
                      _compassChip('E', _kColorE),
                      const SizedBox(width: 12),
                      _compassChip('W', _kColorW),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Room / Furniture / Fill
                  Row(
                    children: [
                      _fsLegendItem(_kColorRoom, 'Room',
                          '${DimensionFormatter.format(widget.roomW)} × '
                          '${DimensionFormatter.format(widget.roomL)} × '
                          '${DimensionFormatter.format(widget.roomH)}'),
                      const SizedBox(width: 16),
                      _fsLegendItem(_kColorFurniture, 'Furniture',
                          '${DimensionFormatter.format(widget.furW)} × '
                          '${DimensionFormatter.format(widget.furL)} × '
                          '${DimensionFormatter.format(widget.furH)}'),
                      const Spacer(),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${fillPercent.toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: fillPercent > 60
                                  ? AppTheme.error
                                  : fillPercent > 40
                                      ? Colors.orange
                                      : AppTheme.success,
                            ),
                          ),
                          const Text('floor area',
                              style: TextStyle(
                                  fontSize: 10, color: Colors.white54)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _compassChip(String letter, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14, height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(letter,
            style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _fsLegendItem(Color color, String label, String dims) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12, height: 12,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                    fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 3),
        Text(dims,
            style: const TextStyle(fontSize: 10, color: Colors.white38)),
      ],
    );
  }
}

// ═══════════════════════════════════════════════
// COLOR PALETTE
// ═══════════════════════════════════════════════

const Color _kColorN = Color(0xFF5C9DFF); // cool blue
const Color _kColorS = Color(0xFFFFD54F); // warm yellow
const Color _kColorE = Color(0xFF81C784); // green
const Color _kColorW = Color(0xFFCE93D8); // purple
const Color _kColorRoom = Color(0xFF90CAF9); // light blue for room dims
const Color _kColorFurniture = Color(0xFFE77050); // orange for furniture

// ═══════════════════════════════════════════════
// ISOMETRIC PROJECTION ENGINE
// ═══════════════════════════════════════════════

const double _kCos30 = 0.8660254037844387;
const double _kSin30 = 0.5;

Offset _iso(double x, double y, double z, Offset origin, double scale) {
  return Offset(
    origin.dx + (x - z) * _kCos30 * scale,
    origin.dy + ((x + z) * _kSin30 - y) * scale,
  );
}

({Offset origin, double scale}) _computeLayout(
    Size canvas, double maxX, double maxY, double maxZ,
    {double padding = 28}) {
  final isoW = (maxX + maxZ) * _kCos30;
  final isoH = maxY + (maxX + maxZ) * _kSin30;
  if (isoW <= 0 || isoH <= 0) {
    return (origin: Offset(canvas.width / 2, canvas.height / 2), scale: 1);
  }

  final scale = math.min(
    (canvas.width - 2 * padding) / isoW,
    (canvas.height - 2 * padding) / isoH,
  );

  final ox = canvas.width / 2 - (maxX - maxZ) * _kCos30 * scale / 2;
  final oy = canvas.height / 2 -
      ((maxX + maxZ) * _kSin30 - maxY) * scale / 2;

  return (origin: Offset(ox, oy), scale: scale);
}

// ─── Floor grid only (clean) ─────────────────

void _drawFloorGrid(Canvas canvas, double maxX, double maxZ,
    Offset origin, double scale) {
  final stepX = _gridStep(maxX);
  final stepZ = _gridStep(maxZ);

  final gridPaint = Paint()
    ..color = Colors.white.withAlpha(20)
    ..strokeWidth = 0.5;

  for (double x = 0; x <= maxX + 0.001; x += stepX) {
    canvas.drawLine(
        _iso(x, 0, 0, origin, scale), _iso(x, 0, maxZ, origin, scale), gridPaint);
  }
  for (double z = 0; z <= maxZ + 0.001; z += stepZ) {
    canvas.drawLine(
        _iso(0, 0, z, origin, scale), _iso(maxX, 0, z, origin, scale), gridPaint);
  }
}

double _gridStep(double axisMax) {
  if (axisMax <= 1) return 0.5;
  if (axisMax <= 3) return 1;
  if (axisMax <= 5) return 1;
  if (axisMax <= 10) return 2;
  return (axisMax / 5).ceilToDouble();
}

double _niceAxisMax(double val) {
  if (val <= 0) return 1;
  if (val <= 1) return 1;
  if (val <= 2) return 2;
  if (val <= 3) return 3;
  if (val <= 5) return 5;
  if (val <= 8) return 8;
  if (val <= 10) return 10;
  if (val <= 15) return 15;
  return (val / 5).ceilToDouble() * 5;
}

void _drawSmallText(Canvas canvas, Offset pos, String text, TextStyle style) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
}

// ─── Solid block drawing ─────────────────────

void _drawSolidBlock(
  Canvas canvas,
  double bx, double by, double bz,
  double bw, double bh, double bd,
  Color color,
  Offset origin,
  double scale, {
  int alpha = 220,
}) {
  final c = [
    _iso(bx, by, bz, origin, scale),
    _iso(bx + bw, by, bz, origin, scale),
    _iso(bx + bw, by + bh, bz, origin, scale),
    _iso(bx, by + bh, bz, origin, scale),
    _iso(bx, by, bz + bd, origin, scale),
    _iso(bx + bw, by, bz + bd, origin, scale),
    _iso(bx + bw, by + bh, bz + bd, origin, scale),
    _iso(bx, by + bh, bz + bd, origin, scale),
  ];

  // Top face
  final topPath = Path()
    ..moveTo(c[3].dx, c[3].dy)
    ..lineTo(c[2].dx, c[2].dy)
    ..lineTo(c[6].dx, c[6].dy)
    ..lineTo(c[7].dx, c[7].dy)
    ..close();
  canvas.drawPath(topPath, Paint()..color = color.withAlpha(alpha));

  // Right face
  final rightFacePath = Path()
    ..moveTo(c[0].dx, c[0].dy)
    ..lineTo(c[1].dx, c[1].dy)
    ..lineTo(c[2].dx, c[2].dy)
    ..lineTo(c[3].dx, c[3].dy)
    ..close();
  canvas.drawPath(
      rightFacePath, Paint()..color = _shade(color, -0.08).withAlpha(alpha));

  // Left face
  final leftFacePath = Path()
    ..moveTo(c[0].dx, c[0].dy)
    ..lineTo(c[4].dx, c[4].dy)
    ..lineTo(c[7].dx, c[7].dy)
    ..lineTo(c[3].dx, c[3].dy)
    ..close();
  canvas.drawPath(
      leftFacePath, Paint()..color = _shade(color, -0.18).withAlpha(alpha));

  // Edges
  final edgePaint = Paint()
    ..color = _shade(color, -0.05).withAlpha(math.min(255, alpha + 35))
    ..strokeWidth = 1.3
    ..style = PaintingStyle.stroke;
  canvas.drawPath(topPath, edgePaint);
  canvas.drawPath(rightFacePath, edgePaint);
  canvas.drawPath(leftFacePath, edgePaint);
}

void _drawWireframeBlock(Canvas canvas, double bx, double by, double bz,
    double bw, double bh, double bd, Color color, Offset origin, double scale,
    {double strokeWidth = 1.0, int alpha = 70}) {
  final c = [
    _iso(bx, by, bz, origin, scale),
    _iso(bx + bw, by, bz, origin, scale),
    _iso(bx + bw, by + bh, bz, origin, scale),
    _iso(bx, by + bh, bz, origin, scale),
    _iso(bx, by, bz + bd, origin, scale),
    _iso(bx + bw, by, bz + bd, origin, scale),
    _iso(bx + bw, by + bh, bz + bd, origin, scale),
    _iso(bx, by + bh, bz + bd, origin, scale),
  ];

  final paint = Paint()
    ..color = color.withAlpha(alpha)
    ..strokeWidth = strokeWidth
    ..style = PaintingStyle.stroke;

  for (final pair in [
    [0, 1], [1, 2], [2, 3], [3, 0],
    [4, 5], [5, 6], [6, 7], [7, 4],
    [0, 4], [1, 5], [2, 6], [3, 7],
  ]) {
    canvas.drawLine(c[pair[0]], c[pair[1]], paint);
  }

  // Subtle floor fill
  final floorPath = Path()
    ..moveTo(c[0].dx, c[0].dy)
    ..lineTo(c[1].dx, c[1].dy)
    ..lineTo(c[5].dx, c[5].dy)
    ..lineTo(c[4].dx, c[4].dy)
    ..close();
  canvas.drawPath(
      floorPath, Paint()..color = color.withAlpha((alpha * 0.12).round()));
}

Color _shade(Color c, double amount) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0)).toColor();
}

Offset _midpoint(Offset a, Offset b) =>
    Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);

void _drawLabelPill(
    Canvas canvas, Offset pos, String text, TextStyle style) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();

  final r = Rect.fromCenter(
      center: pos, width: tp.width + 10, height: tp.height + 6);
  canvas.drawRRect(
    RRect.fromRectAndRadius(r, const Radius.circular(4)),
    Paint()..color = const Color(0xCC1A1A2E),
  );
  tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
}

// ═══════════════════════════════════════════════
// PAINTER: Single block (RoomDimensionView)
// ═══════════════════════════════════════════════

class _SingleBlockPainter extends CustomPainter {
  final double widthM, lengthM, heightM;
  final Color blockColor;

  _SingleBlockPainter({
    required this.widthM,
    required this.lengthM,
    required this.heightM,
    required this.blockColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (widthM <= 0 || lengthM <= 0 || heightM <= 0) return;

    final maxX = _niceAxisMax(widthM);
    final maxY = _niceAxisMax(heightM);
    final maxZ = _niceAxisMax(lengthM);

    final layout = _computeLayout(size, maxX, maxY, maxZ);
    final origin = layout.origin;
    final sc = layout.scale;

    _drawFloorGrid(canvas, maxX, maxZ, origin, sc);

    _drawSolidBlock(canvas, 0, 0, 0, widthM, heightM, lengthM, blockColor,
        origin, sc);

    // Dimension labels
    String fmt(double m) => DimensionFormatter.format(m);
    final style = TextStyle(
      color: blockColor,
      fontSize: 9.5,
      fontWeight: FontWeight.w700,
      shadows: const [Shadow(blurRadius: 3, color: Colors.black)],
    );

    final wMid = _midpoint(
        _iso(0, 0, 0, origin, sc), _iso(widthM, 0, 0, origin, sc));
    _drawLabelPill(canvas, wMid + const Offset(0, 16), fmt(widthM), style);

    final lMid = _midpoint(
        _iso(0, 0, 0, origin, sc), _iso(0, 0, lengthM, origin, sc));
    _drawLabelPill(canvas, lMid + const Offset(-22, 10), fmt(lengthM), style);

    final hMid = _midpoint(
        _iso(0, 0, 0, origin, sc), _iso(0, heightM, 0, origin, sc));
    _drawLabelPill(canvas, hMid + const Offset(-24, -2), fmt(heightM), style);
  }

  @override
  bool shouldRepaint(covariant _SingleBlockPainter o) =>
      o.widthM != widthM || o.lengthM != lengthM || o.heightM != heightM;
}

// ═══════════════════════════════════════════════
// PAINTER: Comparison chart (FurnitureInRoomView)
// ═══════════════════════════════════════════════

class _ComparisonChartPainter extends CustomPainter {
  final double roomW, roomL, roomH;
  final double furW, furL, furH;
  final double? placementX, placementZ, placementRotation;
  final bool showLabels;

  _ComparisonChartPainter({
    required this.roomW,
    required this.roomL,
    required this.roomH,
    required this.furW,
    required this.furL,
    required this.furH,
    this.placementX,
    this.placementZ,
    this.placementRotation,
    this.showLabels = false,
  });

  double get _effFurW {
    final rot = placementRotation ?? 0;
    final cosA = math.cos(rot * math.pi / 180).abs();
    final sinA = math.sin(rot * math.pi / 180).abs();
    return furW * cosA + furL * sinA;
  }

  double get _effFurL {
    final rot = placementRotation ?? 0;
    final cosA = math.cos(rot * math.pi / 180).abs();
    final sinA = math.sin(rot * math.pi / 180).abs();
    return furW * sinA + furL * cosA;
  }

  double get _furDiagramX {
    final px = placementX ?? 0.0;
    return (px + roomW / 2) - _effFurW / 2;
  }

  double get _furDiagramZ {
    final pz = placementZ ?? 0.0;
    return (pz + roomL / 2) - _effFurL / 2;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (roomW <= 0 || roomL <= 0 || roomH <= 0) return;

    final maxX = _niceAxisMax(roomW);
    final maxY = _niceAxisMax(roomH);
    final maxZ = _niceAxisMax(roomL);

    final layout = _computeLayout(size, maxX, maxY, maxZ,
        padding: showLabels ? 44 : 32);
    final origin = layout.origin;
    final sc = layout.scale;

    // 1. Floor grid
    _drawFloorGrid(canvas, maxX, maxZ, origin, sc);

    // 2. Room wireframe (subtle base)
    _drawWireframeBlock(
        canvas, 0, 0, 0, roomW, roomH, roomL, Colors.white, origin, sc,
        alpha: 30, strokeWidth: 0.8);

    // 3. Color-coded wall edges on the floor (N/S/E/W)
    _drawColoredWallEdges(canvas, origin, sc);

    // 4. Furniture floor footprint + solid block
    final fx = _furDiagramX.clamp(0, math.max(0, roomW - _effFurW)).toDouble();
    final fz = _furDiagramZ.clamp(0, math.max(0, roomL - _effFurL)).toDouble();

    // Floor footprint — colored rectangle on y=0 showing base area coverage
    _drawFloorFootprint(canvas, origin, sc, fx, fz, _effFurW, _effFurL);

    // 3D block on top (slightly transparent so footprint edges are visible)
    _drawSolidBlock(canvas, fx, 0, fz, _effFurW, furH, _effFurL,
        _kColorFurniture, origin, sc, alpha: 170);

    // 5. Compass labels (color-coded, always shown)
    _drawCompass(canvas, origin, sc);

    // 6. Dimension labels — fullscreen only
    if (showLabels) {
      _drawRoomLabels(canvas, origin, sc);
      _drawFurnitureLabels(canvas, origin, sc, fx, fz);
    }
  }

  /// Draws a colored rectangle on the floor (y=0) showing furniture base coverage.
  void _drawFloorFootprint(Canvas canvas, Offset origin, double sc,
      double fx, double fz, double fw, double fl) {
    final c0 = _iso(fx, 0, fz, origin, sc);
    final c1 = _iso(fx + fw, 0, fz, origin, sc);
    final c2 = _iso(fx + fw, 0, fz + fl, origin, sc);
    final c3 = _iso(fx, 0, fz + fl, origin, sc);

    final path = Path()
      ..moveTo(c0.dx, c0.dy)
      ..lineTo(c1.dx, c1.dy)
      ..lineTo(c2.dx, c2.dy)
      ..lineTo(c3.dx, c3.dy)
      ..close();

    // Semi-transparent fill
    canvas.drawPath(
        path, Paint()..color = _kColorFurniture.withAlpha(50));

    // Dashed-style border (solid thin line with stronger color)
    canvas.drawPath(
      path,
      Paint()
        ..color = _kColorFurniture.withAlpha(140)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
  }

  /// Draws colored floor edges for each wall direction.
  void _drawColoredWallEdges(Canvas canvas, Offset origin, double sc) {
    final alpha = showLabels ? 180 : 120;
    final width = showLabels ? 2.5 : 2.0;

    // N = back wall (z=roomL floor edge)
    canvas.drawLine(
      _iso(0, 0, roomL, origin, sc),
      _iso(roomW, 0, roomL, origin, sc),
      Paint()..color = _kColorN.withAlpha(alpha)..strokeWidth = width,
    );
    // S = front wall (z=0 floor edge)
    canvas.drawLine(
      _iso(0, 0, 0, origin, sc),
      _iso(roomW, 0, 0, origin, sc),
      Paint()..color = _kColorS.withAlpha(alpha)..strokeWidth = width,
    );
    // E = right wall (x=roomW floor edge)
    canvas.drawLine(
      _iso(roomW, 0, 0, origin, sc),
      _iso(roomW, 0, roomL, origin, sc),
      Paint()..color = _kColorE.withAlpha(alpha)..strokeWidth = width,
    );
    // W = left wall (x=0 floor edge)
    canvas.drawLine(
      _iso(0, 0, 0, origin, sc),
      _iso(0, 0, roomL, origin, sc),
      Paint()..color = _kColorW.withAlpha(alpha)..strokeWidth = width,
    );
  }

  void _drawCompass(Canvas canvas, Offset origin, double sc) {
    final fontSize = showLabels ? 12.0 : 10.0;

    TextStyle s(Color c) => TextStyle(
      color: c,
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      shadows: const [Shadow(blurRadius: 4, color: Colors.black)],
    );

    // N at back wall midpoint
    final nPos = _midpoint(
        _iso(0, 0, roomL, origin, sc), _iso(roomW, 0, roomL, origin, sc));
    _drawSmallText(canvas, nPos + const Offset(0, -14), 'N', s(_kColorN));

    // S at front wall midpoint
    final sPos = _midpoint(
        _iso(0, 0, 0, origin, sc), _iso(roomW, 0, 0, origin, sc));
    _drawSmallText(canvas, sPos + const Offset(0, 14), 'S', s(_kColorS));

    // E at right wall midpoint
    final ePos = _midpoint(
        _iso(roomW, 0, 0, origin, sc), _iso(roomW, 0, roomL, origin, sc));
    _drawSmallText(canvas, ePos + const Offset(14, 0), 'E', s(_kColorE));

    // W at left wall midpoint
    final wPos = _midpoint(
        _iso(0, 0, 0, origin, sc), _iso(0, 0, roomL, origin, sc));
    _drawSmallText(canvas, wPos + const Offset(-14, 0), 'W', s(_kColorW));
  }

  void _drawRoomLabels(Canvas canvas, Offset origin, double sc) {
    String fmt(double m) => DimensionFormatter.format(m);
    final style = TextStyle(
      color: _kColorRoom,
      fontSize: 9.5,
      fontWeight: FontWeight.w700,
      shadows: const [Shadow(blurRadius: 3, color: Colors.black)],
    );

    // Width (X axis — S edge)
    final wMid = _midpoint(
        _iso(0, 0, 0, origin, sc), _iso(roomW, 0, 0, origin, sc));
    _drawLabelPill(canvas, wMid + const Offset(0, 26), 'W: ${fmt(roomW)}', style);

    // Length (Z axis — W edge)
    final lMid = _midpoint(
        _iso(0, 0, 0, origin, sc), _iso(0, 0, roomL, origin, sc));
    _drawLabelPill(canvas, lMid + const Offset(-30, 14), 'L: ${fmt(roomL)}', style);

    // Height (Y axis)
    final hMid = _midpoint(
        _iso(0, 0, 0, origin, sc), _iso(0, roomH, 0, origin, sc));
    _drawLabelPill(canvas, hMid + const Offset(-32, -2), 'H: ${fmt(roomH)}', style);
  }

  void _drawFurnitureLabels(
      Canvas canvas, Offset origin, double sc, double fx, double fz) {
    String fmt(double m) => DimensionFormatter.format(m);
    final ew = _effFurW;
    final el = _effFurL;

    final style = TextStyle(
      color: _kColorFurniture,
      fontSize: 9,
      fontWeight: FontWeight.w700,
      shadows: const [Shadow(blurRadius: 3, color: Colors.black)],
    );

    // Width on top front edge
    final fwMid = _midpoint(
        _iso(fx, furH, fz, origin, sc), _iso(fx + ew, furH, fz, origin, sc));
    _drawLabelPill(canvas, fwMid + const Offset(0, -12), 'w: ${fmt(furW)}', style);

    // Depth on top right edge
    final flMid = _midpoint(
        _iso(fx + ew, furH, fz, origin, sc),
        _iso(fx + ew, furH, fz + el, origin, sc));
    _drawLabelPill(canvas, flMid + const Offset(18, -6), 'l: ${fmt(furL)}', style);

    // Height on right front edge
    final fhMid = _midpoint(
        _iso(fx + ew, 0, fz, origin, sc),
        _iso(fx + ew, furH, fz, origin, sc));
    _drawLabelPill(canvas, fhMid + const Offset(22, 0), 'h: ${fmt(furH)}', style);
  }

  @override
  bool shouldRepaint(covariant _ComparisonChartPainter o) =>
      o.roomW != roomW ||
      o.roomL != roomL ||
      o.roomH != roomH ||
      o.furW != furW ||
      o.furL != furL ||
      o.furH != furH ||
      o.placementX != placementX ||
      o.placementZ != placementZ ||
      o.placementRotation != placementRotation ||
      o.showLabels != showLabels;
}
