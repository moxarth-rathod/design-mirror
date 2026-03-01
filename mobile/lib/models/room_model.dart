/// DesignMirror AI — Room Model
///
/// Represents a saved room scan returned from the backend.

class RoomModel {
  final String id;
  final String roomName;
  final String? roomType;
  final String status;
  final Map<String, dynamic>? dimensions;
  final int planeCount;
  final int pointCount;
  final List<String> photos;
  final DateTime createdAt;

  const RoomModel({
    required this.id,
    required this.roomName,
    this.roomType,
    required this.status,
    this.dimensions,
    required this.planeCount,
    required this.pointCount,
    this.photos = const [],
    required this.createdAt,
  });

  factory RoomModel.fromJson(Map<String, dynamic> json) {
    return RoomModel(
      id: json['id'] as String,
      roomName: json['room_name'] as String,
      roomType: json['room_type'] as String?,
      status: json['status'] as String,
      dimensions: json['dimensions'] as Map<String, dynamic>?,
      planeCount: json['plane_count'] as int,
      pointCount: json['point_count'] as int,
      photos: (json['photos'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  bool get isProcessing => status == 'processing';
  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';
}

