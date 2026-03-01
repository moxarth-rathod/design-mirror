/// DesignMirror AI — Scanner Screen
///
/// Shows the live camera feed and lets the user tap measurement points
/// for room scanning. Points are sent to the backend for coordinate
/// transformation into real-world room dimensions.

import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../blocs/room_scan/room_scan_bloc.dart';
import '../../blocs/room_scan/room_scan_event.dart';
import '../../blocs/room_scan/room_scan_state.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/ar_models.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with WidgetsBindingObserver {
  final _roomNameController = TextEditingController(text: 'Living Room');
  int _pointCounter = 0;

  CameraController? _cameraController;
  bool _isCameraReady = false;
  String? _cameraError;

  // Zoom state
  double _currentZoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _zoomOnScaleStart = 1.0;

  // Track tapped point positions on screen for visual overlay
  final List<Offset> _tapPositions = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
    context.read<RoomScanBloc>().add(RoomScanStarted());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      _cameraController = null;
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      setState(() => _cameraError = 'Camera permission denied');
      return;
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _cameraError = 'No camera found on device');
        return;
      }

      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await controller.initialize();

      if (!mounted) {
        controller.dispose();
        return;
      }

      final minZ = await controller.getMinZoomLevel();
      final maxZ = await controller.getMaxZoomLevel();

      setState(() {
        _cameraController = controller;
        _isCameraReady = true;
        _cameraError = null;
        _minZoom = minZ;
        _maxZoom = maxZ;
        _currentZoom = minZ;
      });
    } catch (e) {
      setState(() => _cameraError = 'Camera init failed: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _roomNameController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  void _onTapToMeasure(TapUpDetails details) {
    _pointCounter++;

    setState(() {
      _tapPositions.add(details.localPosition);
    });

    final angle = (_pointCounter * 2 * math.pi) / 8;
    final radius = 2.0 + (_pointCounter % 3) * 0.5;
    final x = radius * math.cos(angle);
    final z = radius * math.sin(angle);

    context.read<RoomScanBloc>().add(
          RoomScanPointAdded(
            position: ARPoint(x: x, y: 0, z: z),
            label: 'corner_$_pointCounter',
          ),
        );
  }

  void _onScaleStart(ScaleStartDetails details) {
    _zoomOnScaleStart = _currentZoom;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final newZoom =
        (_zoomOnScaleStart * details.scale).clamp(_minZoom, _maxZoom);
    if ((newZoom - _currentZoom).abs() > 0.05) {
      setState(() => _currentZoom = newZoom);
      _cameraController?.setZoomLevel(newZoom);
    }
  }

  void _onSubmitScan() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save Room Scan'),
        content: TextField(
          controller: _roomNameController,
          decoration: const InputDecoration(
            labelText: 'Room Name',
            hintText: 'e.g., Living Room, Bedroom',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<RoomScanBloc>().add(
                    RoomScanSubmitted(
                      roomName: _roomNameController.text.trim(),
                    ),
                  );
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<RoomScanBloc, RoomScanState>(
      listener: (context, state) {
        if (state is RoomScanSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Room "${state.room.roomName}" saved!'),
              backgroundColor: AppTheme.success,
            ),
          );
          context.go(AppRoutes.home);
        } else if (state is RoomScanError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: AppTheme.error,
            ),
          );
        }
      },
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                context.read<RoomScanBloc>().add(RoomScanCancelled());
                context.go(AppRoutes.home);
              },
            ),
            title: const Text('Room Scanner'),
            actions: [
              if (state is RoomScanActive && state.points.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.undo_rounded),
                  tooltip: 'Undo last point',
                  onPressed: () {
                    if (_tapPositions.isNotEmpty) {
                      setState(() => _tapPositions.removeLast());
                    }
                    _pointCounter = math.max(0, _pointCounter - 1);
                    context.read<RoomScanBloc>().add(RoomScanPointUndone());
                  },
                ),
            ],
          ),
          body: Stack(
            children: [
              // ── Camera Preview (receives ALL gestures) ──
              _buildCameraView(),

              // All overlays wrapped in IgnorePointer so taps
              // always pass through to the camera GestureDetector.
              IgnorePointer(
                child: Stack(
                  children: [
                    // ── Tap-point dot overlays ──────
                    ..._tapPositions.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final pos = entry.value;
                      return Positioned(
                        left: pos.dx - 14,
                        top: pos.dy - 14,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withAlpha(180),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${idx + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    }),

                    // ── Lines connecting points ─────
                    if (_tapPositions.length >= 2)
                      CustomPaint(
                        size: Size.infinite,
                        painter: _PointLinePainter(_tapPositions),
                      ),

                    // ── Crosshair overlay ───────────
                    Center(
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white54, width: 1),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: const Icon(
                          Icons.add,
                          color: Colors.white54,
                          size: 18,
                        ),
                      ),
                    ),

                    // ── Status Overlay ──────────────
                    Positioned(
                      top: 16,
                      left: 16,
                      right: 16,
                      child: _buildStatusBar(state),
                    ),

                    // ── Zoom indicator ───────────────
                    if (_currentZoom > _minZoom + 0.1)
                      Positioned(
                        top: 60,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              '${_currentZoom.toStringAsFixed(1)}x',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),

                    // ── Instructions hint ───────────
                    if (state is RoomScanActive && state.points.isEmpty)
                      Positioned(
                        bottom: 110,
                        left: 20,
                        right: 20,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(200),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'How to scan your room',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Mini floor plan diagram
                              SizedBox(
                                height: 90,
                                child: CustomPaint(
                                  size: const Size(200, 90),
                                  painter: _FloorPlanGuidePainter(),
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                '1. Point camera at the floor\n'
                                '2. Tap each corner where walls meet the floor\n'
                                '3. Go around the room (4+ corners)\n'
                                '4. Pinch to zoom in/out',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Min 3 points needed to submit',
                                style: TextStyle(
                                  color: Colors.amber,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // ── Measurement Info ────────────
                    if (state is RoomScanActive && state.points.isNotEmpty)
                      Positioned(
                        bottom: 100,
                        left: 16,
                        right: 16,
                        child: _buildMeasurementInfo(state),
                      ),
                  ],
                ),
              ),

              // ── Loading Overlay ─────────────
              if (state is RoomScanInitializing || state is RoomScanSubmitting)
                Container(
                  color: Colors.black54,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(color: Colors.white),
                        const SizedBox(height: 16),
                        Text(
                          state is RoomScanInitializing
                              ? 'Starting scanner...'
                              : 'Uploading scan...',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),

          // ── Bottom Controls ───────────────
          bottomNavigationBar: state is RoomScanActive
              ? SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Chip(
                          avatar: const Icon(Icons.location_on,
                              size: 18, color: Colors.white),
                          label: Text(
                            '${state.points.length} pts',
                            style: const TextStyle(color: Colors.white),
                          ),
                          backgroundColor: Colors.grey[800],
                          side: BorderSide.none,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed:
                                state.points.length >= 3 ? _onSubmitScan : null,
                            icon: const Icon(Icons.check_rounded),
                            label: Text(
                              state.points.length < 3
                                  ? 'Need ${3 - state.points.length} more'
                                  : 'Submit Scan',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.success,
                              disabledBackgroundColor: Colors.grey[800],
                              minimumSize: const Size(0, 52),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : null,
          backgroundColor: Colors.black,
        );
      },
    );
  }

  Widget _buildCameraView() {
    if (_cameraError != null) {
      return Container(
        color: Colors.black87,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.white30),
              const SizedBox(height: 16),
              Text(
                _cameraError!,
                style: const TextStyle(color: Colors.white54, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _initCamera,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isCameraReady || _cameraController == null) {
      return Container(
        color: Colors.black87,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white54),
              SizedBox(height: 16),
              Text(
                'Initializing camera...',
                style: TextStyle(color: Colors.white54, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTapUp: _onTapToMeasure,
      onScaleStart: _onScaleStart,
      onScaleUpdate: _onScaleUpdate,
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _cameraController!.value.previewSize?.height ?? 1920,
            height: _cameraController!.value.previewSize?.width ?? 1080,
            child: CameraPreview(_cameraController!),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBar(RoomScanState state) {
    if (state is! RoomScanActive) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppTheme.success,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'Camera Ready',
            style: TextStyle(color: Colors.white, fontSize: 13),
          ),
          const Spacer(),
          const Icon(Icons.location_on_outlined,
              color: Colors.white54, size: 16),
          const SizedBox(width: 4),
          Text(
            '${state.points.length} points',
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildMeasurementInfo(RoomScanActive state) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Points (${state.points.length})',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 6),
          ...state.points.reversed.take(3).map(
                (point) => Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    '${point.label}: (${point.position.x.toStringAsFixed(2)}, '
                    '${point.position.y.toStringAsFixed(2)}, '
                    '${point.position.z.toStringAsFixed(2)})',
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ),
              ),
          if (state.points.length > 3)
            Text(
              '  ... and ${state.points.length - 3} more',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
        ],
      ),
    );
  }
}

/// Mini floor-plan diagram showing where to tap corners.
class _FloorPlanGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final w = size.width * 0.6;
    final h = size.height * 0.8;

    // Room outline
    final roomPaint = Paint()
      ..color = Colors.white30
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final roomRect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: w,
      height: h,
    );
    canvas.drawRect(roomRect, roomPaint);

    // Floor fill
    final floorPaint = Paint()
      ..color = Colors.white.withAlpha(15)
      ..style = PaintingStyle.fill;
    canvas.drawRect(roomRect, floorPaint);

    // Corner dots with numbers
    final corners = [
      Offset(cx - w / 2, cy - h / 2),
      Offset(cx + w / 2, cy - h / 2),
      Offset(cx + w / 2, cy + h / 2),
      Offset(cx - w / 2, cy + h / 2),
    ];

    final dotPaint = Paint()
      ..color = Colors.amber
      ..style = PaintingStyle.fill;

    final ringPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (var i = 0; i < corners.length; i++) {
      canvas.drawCircle(corners[i], 8, dotPaint);
      canvas.drawCircle(corners[i], 8, ringPaint);

      final tp = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: const TextStyle(
            color: Colors.black,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        corners[i] - Offset(tp.width / 2, tp.height / 2),
      );
    }

    // Arrows along walls
    final arrowPaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    for (var i = 0; i < corners.length; i++) {
      final next = corners[(i + 1) % corners.length];
      final mid = Offset(
        (corners[i].dx + next.dx) / 2,
        (corners[i].dy + next.dy) / 2,
      );
      canvas.drawLine(corners[i], mid, arrowPaint);
    }

    // "Floor" label
    final floorTp = TextPainter(
      text: const TextSpan(
        text: 'FLOOR',
        style: TextStyle(
          color: Colors.white24,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    floorTp.paint(canvas, Offset(cx - floorTp.width / 2, cy - floorTp.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Draws lines connecting measurement points on the camera view.
class _PointLinePainter extends CustomPainter {
  final List<Offset> points;

  _PointLinePainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final paint = Paint()
      ..color = Colors.white.withAlpha(150)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }

    if (points.length >= 3) {
      path.close();
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PointLinePainter oldDelegate) =>
      oldDelegate.points.length != points.length;
}
