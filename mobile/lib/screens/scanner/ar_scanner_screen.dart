/// DesignMirror AI — AR Scanner Screen
///
/// Uses ARCore for real 3D plane detection, hit testing, and
/// world-anchored measurement points. Tapped points are pinned
/// in 3D space — they remain fixed even as the camera moves.
/// Distances between points are calculated automatically.
///
/// Includes a "Free Tap" fallback mode: once the floor Y-level
/// is known from the first plane tap, subsequent taps can be
/// placed anywhere on screen using a fixed-distance estimate.

import 'dart:async';
import 'dart:math' as math;

import 'package:arcore_flutter_plugin/arcore_flutter_plugin.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import '../../blocs/room_scan/room_scan_bloc.dart';
import '../../blocs/room_scan/room_scan_event.dart';
import '../../blocs/room_scan/room_scan_state.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/ar_models.dart';

const _arChannel = MethodChannel('com.designmirror/arcore');

class ARScannerScreen extends StatefulWidget {
  const ARScannerScreen({super.key});

  @override
  State<ARScannerScreen> createState() => _ARScannerScreenState();
}

class _ARScannerScreenState extends State<ARScannerScreen> {
  final _roomNameController = TextEditingController(text: 'Living Room');

  _ArStatus _arStatus = _ArStatus.checking;
  String? _arError;

  ArCoreController? _arController;
  final List<vm.Vector3> _worldPoints = [];
  int _pointCounter = 0;
  bool _planesDetected = false;
  Timer? _planeTimer;
  Timer? _helpTimer;
  bool _showScanTips = false;

  // Free-tap mode: estimates 3D positions without requiring a detected plane
  bool _freeTapMode = false;
  double? _floorY;

  @override
  void initState() {
    super.initState();
    _checkArCore();
  }

  @override
  void dispose() {
    _planeTimer?.cancel();
    _helpTimer?.cancel();
    _roomNameController.dispose();
    _arController?.dispose();
    super.dispose();
  }

  // ── ARCore Pre-flight ────────────────────────

  Future<void> _checkArCore() async {
    setState(() => _arStatus = _ArStatus.checking);
    try {
      final result =
          await _arChannel.invokeMethod<Map>('checkAvailability') ?? {};
      final status = result['status'] as String? ?? 'unknown';
      final installed = result['installed'] as bool? ?? false;
      if (!mounted) return;

      if (status == 'unsupported') {
        setState(() {
          _arStatus = _ArStatus.unsupported;
          _arError = 'This device does not support ARCore.';
        });
      } else if (!installed) {
        setState(() {
          _arStatus = _ArStatus.needsInstall;
          _arError =
              'Google Play Services for AR is required.\nInstall it to use the AR scanner.';
        });
      } else {
        setState(() => _arStatus = _ArStatus.ready);
        if (mounted) {
          context.read<RoomScanBloc>().add(RoomScanStarted());
        }
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _arStatus = _ArStatus.needsInstall;
        _arError = e.message ?? 'ARCore check failed.';
      });
    }
  }

  Future<void> _installArCore() async {
    try {
      await _arChannel.invokeMethod('openPlayStore');
    } catch (_) {}
  }

  // ── ARCore Callbacks ─────────────────────────

  void _onArCoreViewCreated(ArCoreController controller) {
    _arController = controller;

    controller.onPlaneTap = _onPlaneTap;
    controller.onPlaneDetected = (ArCorePlane plane) {
      if (!_planesDetected && mounted) {
        setState(() => _planesDetected = true);
        _planeTimer?.cancel();
      }
    };

    // Fallback: after 5 seconds let user tap even if callback hasn't fired
    _planeTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && !_planesDetected) {
        setState(() => _planesDetected = true);
      }
    });

    // After 15 seconds, show scanning tips if no points placed
    _helpTimer = Timer(const Duration(seconds: 15), () {
      if (mounted && _worldPoints.isEmpty) {
        setState(() => _showScanTips = true);
      }
    });
  }

  void _onPlaneTap(List<ArCoreHitTestResult> hits) {
    if (hits.isEmpty) return;
    final hit = hits.first;

    final t = hit.pose.translation;
    final point = vm.Vector3(t.x, t.y, t.z);

    // Record floor Y-level from the first real hit
    _floorY ??= t.y.toDouble();

    _addWorldPoint(point);
  }

  void _onFreeTap(TapUpDetails details) {
    if (!_freeTapMode) return;
    if (_floorY == null && _worldPoints.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Place at least one point in Plane mode first to calibrate the floor level.'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 3),
      ));
      return;
    }

    // Estimate a 3D world position at the floor level.
    // Use the last known point as a reference, offset by the tap's
    // screen position relative to the center of the viewport.
    final screenSize = MediaQuery.of(context).size;
    final dx = (details.globalPosition.dx - screenSize.width / 2) / screenSize.width;
    final dz = (details.globalPosition.dy - screenSize.height / 2) / screenSize.height;

    final ref = _worldPoints.isNotEmpty
        ? _worldPoints.last
        : vm.Vector3(0, _floorY ?? 0, 0);

    // Map screen offset to world XZ at ~2m estimated viewing distance
    const estimatedScale = 2.0;
    final point = vm.Vector3(
      ref.x + dx * estimatedScale,
      _floorY ?? ref.y,
      ref.z + dz * estimatedScale,
    );

    _addWorldPoint(point);
  }

  void _addWorldPoint(vm.Vector3 point) {
    _pointCounter++;
    setState(() {
      _worldPoints.add(point);
      _showScanTips = false;
    });

    final sphere = ArCoreSphere(
      radius: 0.025,
      materials: [
        ArCoreMaterial(color: const Color.fromARGB(220, 231, 112, 85))
      ],
    );
    _arController?.addArCoreNodeWithAnchor(ArCoreNode(
      shape: sphere,
      position: vm.Vector3(point.x, point.y, point.z),
      name: 'corner_$_pointCounter',
    ));

    if (_worldPoints.length >= 2) {
      _addLineBetween(_worldPoints[_worldPoints.length - 2], point);
    }

    if (mounted) {
      context.read<RoomScanBloc>().add(RoomScanPointAdded(
            position: ARPoint(x: point.x, y: point.y, z: point.z),
            label: 'corner_$_pointCounter',
          ));
    }
  }

  void _addLineBetween(vm.Vector3 from, vm.Vector3 to) {
    final mid = (from + to) / 2.0;
    final diff = to - from;
    final length = diff.length;
    final dir = diff.normalized();
    final up = vm.Vector3(0, 1, 0);

    vm.Vector4 rot;
    if ((dir - up).length < 0.01 || (dir + up).length < 0.01) {
      rot = vm.Vector4(0, 0, 0, 1);
    } else {
      final cross = up.cross(dir).normalized();
      final angle = math.acos(up.dot(dir).clamp(-1.0, 1.0));
      final h = angle / 2;
      rot = vm.Vector4(cross.x * math.sin(h), cross.y * math.sin(h),
          cross.z * math.sin(h), math.cos(h));
    }

    _arController?.addArCoreNodeWithAnchor(ArCoreNode(
      shape: ArCoreCylinder(
        radius: 0.005,
        height: length,
        materials: [
          ArCoreMaterial(color: const Color.fromARGB(200, 255, 255, 255))
        ],
      ),
      position: vm.Vector3(mid.x, mid.y, mid.z),
      rotation: rot,
      name: 'line_$_pointCounter',
    ));
  }

  void _undoLastPoint() {
    if (_worldPoints.isEmpty) return;
    setState(() {
      _worldPoints.removeLast();
      _pointCounter = math.max(0, _pointCounter - 1);
    });
    _arController?.removeNode(nodeName: 'corner_${_pointCounter + 1}');
    _arController?.removeNode(nodeName: 'line_${_pointCounter + 1}');
    context.read<RoomScanBloc>().add(RoomScanPointUndone());
  }

  void _submitScan() {
    if (_worldPoints.length < 3) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save Room'),
        content: TextField(
          controller: _roomNameController,
          decoration: const InputDecoration(
              labelText: 'Room Name', hintText: 'e.g., Living Room'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<RoomScanBloc>().add(
                  RoomScanSubmitted(roomName: _roomNameController.text.trim()));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  double _distanceBetween(vm.Vector3 a, vm.Vector3 b) => (a - b).length;

  double _totalPerimeter() {
    double t = 0;
    for (int i = 0; i < _worldPoints.length - 1; i++) {
      t += _distanceBetween(_worldPoints[i], _worldPoints[i + 1]);
    }
    if (_worldPoints.length >= 3) {
      t += _distanceBetween(_worldPoints.last, _worldPoints.first);
    }
    return t;
  }

  double _estimatedArea() {
    if (_worldPoints.length < 3) return 0;
    double a = 0;
    final n = _worldPoints.length;
    for (int i = 0; i < n; i++) {
      final j = (i + 1) % n;
      a += _worldPoints[i].x * _worldPoints[j].z;
      a -= _worldPoints[j].x * _worldPoints[i].z;
    }
    return a.abs() / 2;
  }

  // ── Build ────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _arStatus != _ArStatus.ready
          ? _buildPreflightScreen()
          : _buildArScanner(),
    );
  }

  Widget _buildPreflightScreen() {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => context.go(AppRoutes.home)),
                const Spacer(),
                const Text('AR Scanner',
                    style: TextStyle(color: Colors.white, fontSize: 18)),
                const Spacer(),
                const SizedBox(width: 48),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _arStatus == _ArStatus.checking
                          ? Icons.hourglass_top
                          : _arStatus == _ArStatus.unsupported
                              ? Icons.error_outline
                              : Icons.download_rounded,
                      size: 64,
                      color: _arStatus == _ArStatus.unsupported
                          ? AppTheme.error
                          : Colors.amber,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _arStatus == _ArStatus.checking
                          ? 'Checking ARCore…'
                          : _arStatus == _ArStatus.unsupported
                              ? 'ARCore Not Supported'
                              : 'ARCore Required',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    if (_arStatus == _ArStatus.checking)
                      const CircularProgressIndicator(color: Colors.amber),
                    if (_arError != null) ...[
                      Text(_arError!,
                          style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              height: 1.6),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 24),
                    ],
                    if (_arStatus == _ArStatus.needsInstall) ...[
                      ElevatedButton.icon(
                        onPressed: _installArCore,
                        icon: const Icon(Icons.shop),
                        label: const Text('Install from Play Store'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                          minimumSize: const Size(240, 52),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _checkArCore,
                        child: const Text('Check Again',
                            style: TextStyle(color: Colors.white54)),
                      ),
                    ],
                    if (_arStatus == _ArStatus.unsupported) ...[
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: () => context.go(AppRoutes.manualRoom),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white38),
                          minimumSize: const Size(240, 48),
                        ),
                        child: const Text('Use Manual Entry Instead'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArScanner() {
    return BlocConsumer<RoomScanBloc, RoomScanState>(
      listener: (context, state) {
        if (state is RoomScanSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Room "${state.room.roomName}" saved!'),
            backgroundColor: AppTheme.success,
          ));
          context.go(AppRoutes.home);
        } else if (state is RoomScanError) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(state.message),
            backgroundColor: AppTheme.error,
          ));
        }
      },
      builder: (context, state) {
        return Stack(
          children: [
            // ── AR View (receives all taps in normal mode) ──
            ArCoreView(
              onArCoreViewCreated: _onArCoreViewCreated,
              enableTapRecognizer: true,
              enablePlaneRenderer: true,
              enableUpdateListener: true,
            ),

            // ── Free-tap overlay (only active in free-tap mode) ──
            if (_freeTapMode)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapUp: _onFreeTap,
                  child: Container(color: Colors.transparent),
                ),
              ),

            // ── All non-interactive overlays ──
            IgnorePointer(
              child: Stack(
                children: [
                  // Status badge
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 8,
                    left: 70,
                    right: 70,
                    child: Center(child: _buildStatusBadge()),
                  ),

                  // Instruction panel (before first point)
                  if (_planesDetected && _worldPoints.isEmpty)
                    Positioned(
                      bottom: 130,
                      left: 20,
                      right: 20,
                      child: _buildInstructionPanel(),
                    ),

                  // Scanning tips (appears after 15s with no taps)
                  if (_showScanTips)
                    Positioned(
                      bottom: 130,
                      left: 20,
                      right: 20,
                      child: _buildScanTips(),
                    ),

                  // Measurement summary
                  if (_worldPoints.length >= 2)
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 44,
                      left: 16,
                      right: 16,
                      child: _buildMeasurementSummary(),
                    ),
                ],
              ),
            ),

            // ── Interactive buttons ──
            // Close
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 16,
              child: _circleBtn(Icons.close, () {
                context.read<RoomScanBloc>().add(RoomScanCancelled());
                context.go(AppRoutes.home);
              }),
            ),

            // Undo
            if (_worldPoints.isNotEmpty)
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                right: 16,
                child: _circleBtn(Icons.undo, _undoLastPoint),
              ),

            // Free-tap mode toggle (shown after plane detected)
            if (_planesDetected)
              Positioned(
                top: MediaQuery.of(context).padding.top + 56,
                right: 16,
                child: _buildFreeTapToggle(),
              ),

            // Manual entry fallback
            if (_showScanTips)
              Positioned(
                bottom: 90,
                left: 20,
                right: 20,
                child: Center(
                  child: TextButton.icon(
                    onPressed: () => context.go(AppRoutes.manualRoom),
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Switch to Manual Entry'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white70,
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ),

            // Bottom controls
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildBottomControls(state),
            ),
          ],
        );
      },
    );
  }

  // ── Sub-widgets ──────────────────────────────

  Widget _buildStatusBadge() {
    String text;
    Color bg;
    IconData icon;

    if (!_planesDetected) {
      text = 'Move phone slowly across floor…';
      bg = Colors.orange.withAlpha(200);
      icon = Icons.sensors;
    } else if (_worldPoints.isEmpty) {
      text = _freeTapMode
          ? 'Free mode — tap anywhere on screen'
          : 'Tap highlighted areas on the floor';
      bg = Colors.blue.withAlpha(200);
      icon = Icons.touch_app;
    } else {
      text = _freeTapMode
          ? '${_worldPoints.length} pts · Free tap mode'
          : '${_worldPoints.length} pts · Tap next corner';
      bg = AppTheme.success.withAlpha(200);
      icon = Icons.check_circle;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(text,
                style: const TextStyle(color: Colors.white, fontSize: 11),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(200),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.touch_app, color: Colors.amber, size: 28),
          const SizedBox(height: 8),
          Text(
            _freeTapMode
                ? 'Free Tap mode — tap anywhere to place corners.\n'
                    'Accuracy depends on your phone position.'
                : 'Tap the shaded/highlighted areas on the floor\n'
                    'where the walls meet to mark room corners.',
            style: const TextStyle(
                color: Colors.white, fontSize: 13, height: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          if (!_freeTapMode)
            const Text(
              'The highlighted overlay = tappable surface.\n'
              'Move phone slowly to expand detection area.',
              style: TextStyle(
                  color: Colors.white54, fontSize: 11, height: 1.4),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }

  Widget _buildScanTips() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(220),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amber.withAlpha(80)),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, color: Colors.amber, size: 20),
              SizedBox(width: 8),
              Text('Scanning Tips',
                  style: TextStyle(
                      color: Colors.amber,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          SizedBox(height: 10),
          _TipRow(icon: Icons.wb_sunny_outlined, text: 'Ensure good lighting'),
          SizedBox(height: 6),
          _TipRow(
              icon: Icons.texture,
              text: 'Aim at textured surfaces (not plain white)'),
          SizedBox(height: 6),
          _TipRow(
              icon: Icons.slow_motion_video,
              text: 'Move phone slowly left & right'),
          SizedBox(height: 6),
          _TipRow(
              icon: Icons.zoom_in,
              text: 'Hold phone 1–2m above the floor'),
          SizedBox(height: 10),
          Text('Or try "Free Tap" mode (⋮ button) to tap anywhere',
              style: TextStyle(color: Colors.white38, fontSize: 10),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildMeasurementSummary() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(180),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ..._buildWallMeasurements(),
          if (_worldPoints.length >= 3) ...[
            const Divider(color: Colors.white24, height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _stat('Perimeter',
                    '${_totalPerimeter().toStringAsFixed(2)}m'),
                _stat('Area',
                    '${_estimatedArea().toStringAsFixed(2)} m²'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFreeTapToggle() {
    return GestureDetector(
      onTap: () {
        setState(() => _freeTapMode = !_freeTapMode);
        if (_freeTapMode && _floorY == null && _worldPoints.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Tip: Place one point in normal mode first for better accuracy.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ));
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: _freeTapMode
              ? Colors.amber.withAlpha(200)
              : Colors.black54,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _freeTapMode ? Colors.amber : Colors.white24,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _freeTapMode ? Icons.touch_app : Icons.ads_click,
              color: _freeTapMode ? Colors.black : Colors.white70,
              size: 16,
            ),
            const SizedBox(width: 4),
            Text(
              _freeTapMode ? 'FREE' : 'Free',
              style: TextStyle(
                color: _freeTapMode ? Colors.black : Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls(RoomScanState state) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).padding.bottom + 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withAlpha(220)],
        ),
      ),
      child: Row(
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.location_on,
                    color: Colors.amber, size: 18),
                const SizedBox(width: 4),
                Text('${_worldPoints.length}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed:
                  _worldPoints.length >= 3 && state is! RoomScanSubmitting
                      ? _submitScan
                      : null,
              icon: state is RoomScanSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_rounded),
              label: Text(_worldPoints.length < 3
                  ? 'Need ${3 - _worldPoints.length} more'
                  : 'Save Room'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.success,
                disabledBackgroundColor: Colors.grey[800],
                minimumSize: const Size(0, 52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildWallMeasurements() {
    final walls = <Widget>[];
    for (int i = 0; i < _worldPoints.length - 1; i++) {
      final d = _distanceBetween(_worldPoints[i], _worldPoints[i + 1]);
      walls.add(Text(
        'Wall ${i + 1}: ${d.toStringAsFixed(2)}m (${(d * 3.28084).toStringAsFixed(1)}ft)',
        style: const TextStyle(color: Colors.white70, fontSize: 11),
      ));
    }
    if (_worldPoints.length >= 3) {
      final d = _distanceBetween(_worldPoints.last, _worldPoints.first);
      walls.add(Text(
        'Closing: ${d.toStringAsFixed(2)}m (${(d * 3.28084).toStringAsFixed(1)}ft)',
        style: const TextStyle(color: Colors.amber, fontSize: 11),
      ));
    }
    return walls;
  }

  Widget _circleBtn(IconData icon, VoidCallback onPressed) {
    return CircleAvatar(
      backgroundColor: Colors.black54,
      child: IconButton(
          icon: Icon(icon, color: Colors.white, size: 20),
          onPressed: onPressed),
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white38, fontSize: 10)),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ── Stateless tip row widget ──────────────────

class _TipRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _TipRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white54, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 11, height: 1.3)),
        ),
      ],
    );
  }
}

enum _ArStatus { checking, ready, needsInstall, unsupported }
