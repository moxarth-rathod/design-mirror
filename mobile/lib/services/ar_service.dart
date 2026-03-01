/// DesignMirror AI — AR Service
///
/// Manages the AR session lifecycle and translates platform-specific
/// AR data into our cross-platform [ARPlane] and [MeasurementPoint] models.
///
/// MENTOR MOMENT: How AR Plane Detection Works
/// ════════════════════════════════════════════
///
/// When the phone camera runs, ARKit (iOS) / ARCore (Android) does this:
///
/// 1. **Feature Point Detection**
///    The AR engine identifies visual "features" in the camera feed —
///    corners, edges, textures. It tracks these across video frames.
///
/// 2. **Plane Estimation**
///    When enough feature points cluster on a flat surface, the engine
///    "fits" a geometric plane to them. Initially small, the plane grows
///    as the user moves the camera and more points are discovered.
///
/// 3. **Coordinate System**
///    The AR engine creates a 3D coordinate system:
///      • Origin (0,0,0) = where the phone was when AR started
///      • Y-axis = up (gravity direction)
///      • X-axis = right
///      • Z-axis = towards the user
///    All planes and points are relative to this coordinate system.
///
/// 4. **World Tracking**
///    The phone continuously tracks its own position and rotation within
///    this coordinate system (called "6DOF" — 6 Degrees of Freedom).
///    This is how it knows where to place virtual furniture.
///
/// 5. **LiDAR Enhancement (iPhone 12 Pro+)**
///    LiDAR shoots invisible laser pulses and measures the time they
///    take to bounce back. This gives EXACT depth measurements
///    (sub-inch accuracy) instead of relying on visual estimation.

import 'dart:async';
import 'dart:io';

import 'package:logger/logger.dart';

import '../config/app_config.dart';
import '../models/ar_models.dart';

/// Enum representing the current state of the AR session.
enum ARSessionState {
  /// AR is initializing (loading assets, calibrating).
  initializing,

  /// AR is running and detecting planes.
  tracking,

  /// AR tracking quality is degraded (poor lighting, fast movement).
  limited,

  /// AR is not available on this device.
  notAvailable,

  /// AR session has ended.
  stopped,
}

/// Service that manages AR plane detection and measurement collection.
///
/// This is an abstraction layer over ARKit/ARCore. The scanner screen
/// interacts with this service, not the platform plugins directly.
class ARService {
  final Logger _logger = Logger();

  // ── State ──────────────────────────────────
  final List<ARPlane> _detectedPlanes = [];
  final List<MeasurementPoint> _measurementPoints = [];
  ARSessionState _state = ARSessionState.stopped;

  // ── Stream Controllers ─────────────────────
  // Streams allow the UI to reactively update when new planes are detected.
  final _planeController = StreamController<List<ARPlane>>.broadcast();
  final _stateController = StreamController<ARSessionState>.broadcast();
  final _pointController = StreamController<List<MeasurementPoint>>.broadcast();

  // ── Public Streams ─────────────────────────
  Stream<List<ARPlane>> get planesStream => _planeController.stream;
  Stream<ARSessionState> get stateStream => _stateController.stream;
  Stream<List<MeasurementPoint>> get pointsStream => _pointController.stream;

  // ── Public Getters ─────────────────────────
  List<ARPlane> get detectedPlanes => List.unmodifiable(_detectedPlanes);
  List<MeasurementPoint> get measurementPoints =>
      List.unmodifiable(_measurementPoints);
  ARSessionState get state => _state;
  bool get isTracking => _state == ARSessionState.tracking;

  /// Check if the current device supports AR.
  Future<bool> checkARAvailability() async {
    // iOS: ARKit requires A9 chip (iPhone 6s+)
    // Android: ARCore requires specific device models
    if (Platform.isIOS) {
      // ARKit is available on most modern iOS devices
      return true;
    } else if (Platform.isAndroid) {
      // ARCore availability would be checked via the plugin
      return true;
    }
    return false;
  }

  /// Check if the device has a LiDAR sensor.
  bool get hasLidar {
    // LiDAR is available on iPhone 12 Pro+ and iPad Pro 2020+.
    // In production, we'd check the device model. For now, this is
    // a placeholder that would be set based on ARKit's capabilities.
    if (Platform.isIOS) {
      // TODO: Check actual device capabilities via ARKit
      return false;
    }
    return false;
  }

  // ── Session Lifecycle ──────────────────────

  /// Start the AR session and begin plane detection.
  Future<void> startSession() async {
    _logger.i('Starting AR session...');
    _updateState(ARSessionState.initializing);

    final isAvailable = await checkARAvailability();
    if (!isAvailable) {
      _updateState(ARSessionState.notAvailable);
      _logger.w('AR is not available on this device');
      return;
    }

    // Clear any previous session data
    _detectedPlanes.clear();
    _measurementPoints.clear();

    // In a real implementation, this is where we'd configure and start
    // the ARKit/ARCore session via the platform plugin.
    // The plugin would call our callbacks as planes are detected.
    _updateState(ARSessionState.tracking);
    _logger.i('AR session started — tracking');
  }

  /// Stop the AR session and release resources.
  Future<void> stopSession() async {
    _logger.i('Stopping AR session...');
    _updateState(ARSessionState.stopped);
    // Platform plugin would release the AR session here
  }

  // ── Plane Detection Callbacks ──────────────
  // These methods are called by the platform-specific AR plugin
  // when planes are detected, updated, or removed.

  /// Called when a new plane is detected by ARKit/ARCore.
  void onPlaneDetected(ARPlane plane) {
    // Filter out planes that are too small (noise)
    if (plane.extent.area < AppConfig.arMinPlaneArea) {
      _logger.d('Plane ${plane.id} ignored — too small (${plane.extent.area} m²)');
      return;
    }

    _detectedPlanes.add(plane);
    _planeController.add(_detectedPlanes);
    _logger.i(
      'Plane detected: ${plane.type.name} at (${plane.center.x.toStringAsFixed(2)}, '
      '${plane.center.y.toStringAsFixed(2)}, ${plane.center.z.toStringAsFixed(2)}) — '
      '${plane.extent.width.toStringAsFixed(2)}m × ${plane.extent.height.toStringAsFixed(2)}m',
    );
  }

  /// Called when an existing plane is updated (expanded/refined).
  void onPlaneUpdated(ARPlane updatedPlane) {
    final index =
        _detectedPlanes.indexWhere((p) => p.id == updatedPlane.id);
    if (index != -1) {
      _detectedPlanes[index] = updatedPlane;
      _planeController.add(_detectedPlanes);
    }
  }

  /// Called when a plane is removed (merged with another or lost).
  void onPlaneRemoved(String planeId) {
    _detectedPlanes.removeWhere((p) => p.id == planeId);
    _planeController.add(_detectedPlanes);
  }

  // ── Measurement Points ─────────────────────

  /// Add a measurement point when the user taps on a detected plane.
  ///
  /// The [position] is in AR world coordinates (meters from origin).
  /// The [label] describes what this point represents (e.g., "wall_corner_1").
  void addMeasurementPoint(ARPoint position, String label) {
    final point = MeasurementPoint(position: position, label: label);
    _measurementPoints.add(point);
    _pointController.add(_measurementPoints);
    _logger.i(
      'Measurement point added: "$label" at '
      '(${position.x.toStringAsFixed(3)}, ${position.y.toStringAsFixed(3)}, '
      '${position.z.toStringAsFixed(3)})',
    );
  }

  /// Remove the last measurement point (undo).
  void undoLastPoint() {
    if (_measurementPoints.isNotEmpty) {
      final removed = _measurementPoints.removeLast();
      _pointController.add(_measurementPoints);
      _logger.i('Measurement point undone: "${removed.label}"');
    }
  }

  /// Clear all measurement points (reset).
  void clearPoints() {
    _measurementPoints.clear();
    _pointController.add(_measurementPoints);
    _logger.i('All measurement points cleared');
  }

  // ── Build Scan Data ────────────────────────

  /// Package all collected data into a [RoomScanData] object
  /// ready to send to the backend.
  RoomScanData buildScanData(String roomName) {
    return RoomScanData(
      roomName: roomName,
      planes: List.from(_detectedPlanes),
      measurementPoints: List.from(_measurementPoints),
      deviceInfo: DeviceInfo(
        hasLidar: hasLidar,
        trackingQuality: _state == ARSessionState.tracking ? 'normal' : 'limited',
      ),
    );
  }

  // ── Internal ───────────────────────────────

  void _updateState(ARSessionState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  /// Release all resources. Call when the service is no longer needed.
  void dispose() {
    _planeController.close();
    _stateController.close();
    _pointController.close();
  }
}

