/// DesignMirror AI — AR Data Models
///
/// MENTOR MOMENT: How AR Data Flows from Phone to Backend
/// ═══════════════════════════════════════════════════════
///
/// When the user scans their room, here's what happens:
///
/// 1. ARKit/ARCore detects flat surfaces (floors, walls, tables).
///    Each surface is an "AR Plane" with a position and size in 3D space.
///
/// 2. The phone's AR engine tracks the camera position and orientation,
///    creating a coordinate system where (0,0,0) is where the phone started.
///
/// 3. The user taps points on detected planes to mark room boundaries.
///    Each tap creates a "measurement point" — a 3D coordinate in the
///    AR world coordinate system.
///
/// 4. When the scan is complete, the app packages all this data into a
///    JSON object (a RoomScanData) and sends it to the Python backend.
///
/// 5. The backend's Coordinate Transformation Service converts these
///    AR-relative coordinates into real-world measurements (meters/feet).
///
/// The JSON packet looks like:
/// ```json
/// {
///   "room_name": "Living Room",
///   "planes": [
///     {
///       "id": "plane_001",
///       "type": "floor",
///       "center": {"x": 0.0, "y": 0.0, "z": -2.5},
///       "extent": {"width": 4.2, "height": 3.1},
///       "transform": [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,-2.5,1]
///     }
///   ],
///   "measurement_points": [
///     {"x": -2.1, "y": 0.0, "z": -1.0, "label": "wall_corner_1"},
///     {"x":  2.1, "y": 0.0, "z": -1.0, "label": "wall_corner_2"}
///   ],
///   "device_info": {
///     "has_lidar": true,
///     "tracking_quality": "normal"
///   }
/// }
/// ```

/// A 3D point in AR world coordinate space.
class ARPoint {
  final double x;
  final double y;
  final double z;

  const ARPoint({
    required this.x,
    required this.y,
    required this.z,
  });

  factory ARPoint.fromJson(Map<String, dynamic> json) {
    return ARPoint(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      z: (json['z'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'z': z};

  /// Calculate Euclidean distance to another point (in meters).
  double distanceTo(ARPoint other) {
    final dx = x - other.x;
    final dy = y - other.y;
    final dz = z - other.z;
    return (dx * dx + dy * dy + dz * dz).sqrt();
  }

  @override
  String toString() => 'ARPoint($x, $y, $z)';
}

/// Extension to add sqrt to double
extension on double {
  double sqrt() {
    // Using dart:math would require an import at the top.
    // For simplicity, we use this workaround.
    return this < 0 ? 0 : _sqrt(this);
  }

  static double _sqrt(double value) {
    if (value == 0) return 0;
    double guess = value / 2;
    for (int i = 0; i < 20; i++) {
      guess = (guess + value / guess) / 2;
    }
    return guess;
  }
}

/// A labeled measurement point (user-tapped location).
class MeasurementPoint {
  final ARPoint position;
  final String label;

  const MeasurementPoint({
    required this.position,
    required this.label,
  });

  factory MeasurementPoint.fromJson(Map<String, dynamic> json) {
    return MeasurementPoint(
      position: ARPoint(
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        z: (json['z'] as num).toDouble(),
      ),
      label: json['label'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        ...position.toJson(),
        'label': label,
      };
}

/// The 2D extent (size) of a detected AR plane.
class PlaneExtent {
  final double width;
  final double height;

  const PlaneExtent({required this.width, required this.height});

  double get area => width * height;

  factory PlaneExtent.fromJson(Map<String, dynamic> json) {
    return PlaneExtent(
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {'width': width, 'height': height};
}

/// Type of AR plane detected.
enum ARPlaneType {
  floor,
  wall,
  ceiling,
  table,
  seat,
  unknown;

  static ARPlaneType fromString(String value) {
    return ARPlaneType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ARPlaneType.unknown,
    );
  }
}

/// A detected AR plane (floor, wall, etc.).
class ARPlane {
  final String id;
  final ARPlaneType type;
  final ARPoint center;
  final PlaneExtent extent;
  final List<double>? transform; // 4x4 transformation matrix (column-major)

  const ARPlane({
    required this.id,
    required this.type,
    required this.center,
    required this.extent,
    this.transform,
  });

  factory ARPlane.fromJson(Map<String, dynamic> json) {
    return ARPlane(
      id: json['id'] as String,
      type: ARPlaneType.fromString(json['type'] as String),
      center: ARPoint.fromJson(json['center'] as Map<String, dynamic>),
      extent: PlaneExtent.fromJson(json['extent'] as Map<String, dynamic>),
      transform: (json['transform'] as List<dynamic>?)
          ?.map((e) => (e as num).toDouble())
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'center': center.toJson(),
        'extent': extent.toJson(),
        'transform': transform,
      };
}

/// Device capability information sent with scan data.
class DeviceInfo {
  final bool hasLidar;
  final String trackingQuality; // "normal", "limited", "not_available"

  const DeviceInfo({
    required this.hasLidar,
    required this.trackingQuality,
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      hasLidar: json['has_lidar'] as bool,
      trackingQuality: json['tracking_quality'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'has_lidar': hasLidar,
        'tracking_quality': trackingQuality,
      };
}

/// Complete room scan data sent to the backend.
class RoomScanData {
  final String roomName;
  final List<ARPlane> planes;
  final List<MeasurementPoint> measurementPoints;
  final DeviceInfo deviceInfo;

  const RoomScanData({
    required this.roomName,
    required this.planes,
    required this.measurementPoints,
    required this.deviceInfo,
  });

  Map<String, dynamic> toJson() => {
        'room_name': roomName,
        'planes': planes.map((p) => p.toJson()).toList(),
        'measurement_points':
            measurementPoints.map((mp) => mp.toJson()).toList(),
        'device_info': deviceInfo.toJson(),
      };

  factory RoomScanData.fromJson(Map<String, dynamic> json) {
    return RoomScanData(
      roomName: json['room_name'] as String,
      planes: (json['planes'] as List<dynamic>)
          .map((p) => ARPlane.fromJson(p as Map<String, dynamic>))
          .toList(),
      measurementPoints: (json['measurement_points'] as List<dynamic>)
          .map((mp) => MeasurementPoint.fromJson(mp as Map<String, dynamic>))
          .toList(),
      deviceInfo:
          DeviceInfo.fromJson(json['device_info'] as Map<String, dynamic>),
    );
  }
}

