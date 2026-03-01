import 'package:arcore_flutter_plugin/arcore_flutter_plugin.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import '../../config/theme.dart';

const _arChannel = MethodChannel('com.designmirror/arcore');

class ARPreviewScreen extends StatefulWidget {
  final String productName;
  final double widthM;
  final double depthM;
  final double heightM;
  final String? modelUrl;

  const ARPreviewScreen({
    super.key,
    required this.productName,
    required this.widthM,
    required this.depthM,
    required this.heightM,
    this.modelUrl,
  });

  static ARPreviewScreen fromRoute(GoRouterState state) {
    final params = state.uri.queryParameters;
    return ARPreviewScreen(
      productName: params['productName'] ?? 'Furniture',
      widthM: double.tryParse(params['widthM'] ?? '1') ?? 1,
      depthM: double.tryParse(params['depthM'] ?? '1') ?? 1,
      heightM: double.tryParse(params['heightM'] ?? '0.8') ?? 0.8,
      modelUrl: params['modelUrl'],
    );
  }

  @override
  State<ARPreviewScreen> createState() => _ARPreviewScreenState();
}

class _ARPreviewScreenState extends State<ARPreviewScreen> {
  ArCoreController? _arController;
  bool _placed = false;
  bool _useModelMode = false;
  String _statusText = 'Point camera at floor, tap to place';
  bool _arAvailable = false;
  bool _checking = true;
  String? _arError;
  bool _planesDetected = false;
  bool _showInstructions = true;

  @override
  void initState() {
    super.initState();
    _checkArCore();
  }

  @override
  void dispose() {
    _arController?.dispose();
    super.dispose();
  }

  Future<void> _checkArCore() async {
    setState(() {
      _checking = true;
      _arError = null;
    });
    try {
      final result =
          await _arChannel.invokeMethod<Map>('checkAvailability') ?? {};
      final status = result['status'] as String? ?? 'unknown';
      final installed = result['installed'] as bool? ?? false;
      if (!mounted) return;

      if (status == 'unsupported') {
        setState(() {
          _arAvailable = false;
          _checking = false;
          _arError = 'This device does not support ARCore.';
        });
      } else if (!installed) {
        setState(() {
          _arAvailable = false;
          _checking = false;
          _arError =
              'Google Play Services for AR is required.\nInstall it to use AR preview.';
        });
      } else {
        setState(() {
          _arAvailable = true;
          _checking = false;
        });
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _arAvailable = false;
        _checking = false;
        _arError = e.message ?? 'ARCore check failed.';
      });
    }
  }

  Future<void> _installArCore() async {
    try {
      await _arChannel.invokeMethod('openPlayStore');
    } catch (_) {}
  }

  void _onArCoreViewCreated(ArCoreController controller) {
    _arController = controller;
    controller.onPlaneTap = _onPlaneTap;
    controller.onPlaneDetected = (_) {
      if (mounted && !_planesDetected) {
        setState(() => _planesDetected = true);
      }
    };
  }

  void _onPlaneTap(List<ArCoreHitTestResult> hits) {
    if (hits.isEmpty) return;
    final hit = hits.first;
    final t = hit.pose.translation;

    _arController?.removeNode(nodeName: 'furniture_preview');

    if (_useModelMode && widget.modelUrl != null && widget.modelUrl!.isNotEmpty) {
      _placeModel(vm.Vector3(t.x, t.y, t.z));
    } else {
      _placeBox(vm.Vector3(t.x, t.y + widget.heightM / 2, t.z));
    }

    if (mounted) {
      setState(() {
        _placed = true;
        _statusText = 'Furniture placed! Tap elsewhere to reposition.';
        _showInstructions = false;
      });
    }
  }

  void _placeModel(vm.Vector3 floorPos) {
    try {
      final node = ArCoreReferenceNode(
        name: 'furniture_preview',
        objectUrl: widget.modelUrl,
        position: floorPos,
        scale: vm.Vector3.all(1.0),
      );
      _arController?.addArCoreNodeWithAnchor(node);
    } catch (_) {
      _placeBox(vm.Vector3(floorPos.x, floorPos.y + widget.heightM / 2, floorPos.z));
      if (mounted) {
        setState(() => _statusText = '3D model failed — showing box instead');
      }
    }
  }

  void _placeBox(vm.Vector3 pos) {
    final cube = ArCoreCube(
      size: vm.Vector3(widget.widthM, widget.heightM, widget.depthM),
      materials: [
        ArCoreMaterial(color: Colors.blue.withOpacity(0.6)),
      ],
    );
    _arController?.addArCoreNodeWithAnchor(ArCoreNode(
      name: 'furniture_preview',
      shape: cube,
      position: pos,
    ));
  }

  void _reset() {
    _arController?.removeNode(nodeName: 'furniture_preview');
    if (mounted) {
      setState(() {
        _placed = false;
        _statusText = 'Point camera at floor, tap to place';
        _showInstructions = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _checking || !_arAvailable
          ? _buildPreflightScreen()
          : _buildArView(),
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
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => context.pop(),
                ),
                const Spacer(),
                const Text(
                  'AR Preview',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
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
                      _checking
                          ? Icons.hourglass_top
                          : Icons.error_outline,
                      size: 64,
                      color: _checking
                          ? AppTheme.accent
                          : AppTheme.error,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _checking ? 'Checking ARCore…' : 'ARCore Required',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_checking)
                      const CircularProgressIndicator(color: AppTheme.accent),
                    if (_arError != null) ...[
                      Text(
                        _arError!,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          height: 1.6,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                    ],
                    if (!_checking && _arError != null) ...[
                      ElevatedButton.icon(
                        onPressed: _installArCore,
                        icon: const Icon(Icons.shop),
                        label: const Text('Install from Play Store'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                          minimumSize: const Size(240, 52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _checkArCore,
                        child: const Text(
                          'Check Again',
                          style: TextStyle(color: Colors.white54),
                        ),
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

  Widget _buildArView() {
    return Stack(
      children: [
        ArCoreView(
          onArCoreViewCreated: _onArCoreViewCreated,
          enableTapRecognizer: true,
          enablePlaneRenderer: true,
          enableUpdateListener: true,
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 16,
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => context.pop(),
          ),
        ),
        IgnorePointer(
          child: Stack(
            children: [
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 70,
                right: 70,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _statusText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              if (_showInstructions && !_placed)
                Positioned(
                  bottom: 180,
                  left: 24,
                  right: 24,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.touch_app,
                          color: AppTheme.accent,
                          size: 28,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Move your phone slowly to detect the floor.\n'
                          'Tap on highlighted areas to place the furniture.',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: EdgeInsets.fromLTRB(
              20,
              16,
              20,
              MediaQuery.of(context).padding.bottom + 16,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withOpacity(0.85),
                ],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.surface.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inventory_2_outlined, color: AppTheme.accent, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        '${widget.productName} · '
                        '${widget.widthM.toStringAsFixed(1)}×${widget.depthM.toStringAsFixed(1)}×${widget.heightM.toStringAsFixed(1)}m',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (widget.modelUrl != null && widget.modelUrl!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: false,
                          label: Text('Box'),
                          icon: Icon(Icons.view_in_ar, size: 18),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text('3D Model'),
                          icon: Icon(Icons.threed_rotation, size: 18),
                        ),
                      ],
                      selected: {_useModelMode},
                      onSelectionChanged: (v) {
                        setState(() => _useModelMode = v.first);
                        if (_placed) _reset();
                      },
                      style: ButtonStyle(
                        backgroundColor: MaterialStateProperty.resolveWith((states) {
                          if (states.contains(MaterialState.selected)) {
                            return AppTheme.accent;
                          }
                          return Colors.white24;
                        }),
                        foregroundColor: const MaterialStatePropertyAll(Colors.white),
                      ),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _placed ? _reset : null,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Reset'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: _placed ? Colors.white54 : Colors.white24,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
