/// DesignMirror AI — Room Scan BLoC States

import 'package:equatable/equatable.dart';

import '../../models/ar_models.dart';
import '../../models/room_model.dart';

abstract class RoomScanState extends Equatable {
  const RoomScanState();

  @override
  List<Object?> get props => [];
}

/// Initial state — scanner not yet started.
class RoomScanInitial extends RoomScanState {}

/// AR session is initializing.
class RoomScanInitializing extends RoomScanState {}

/// Actively scanning — contains current planes and measurement points.
class RoomScanActive extends RoomScanState {
  final List<ARPlane> planes;
  final List<MeasurementPoint> points;
  final bool isTrackingNormal;

  const RoomScanActive({
    required this.planes,
    required this.points,
    this.isTrackingNormal = true,
  });

  @override
  List<Object?> get props => [planes.length, points.length, isTrackingNormal];

  /// Create a copy with updated values.
  RoomScanActive copyWith({
    List<ARPlane>? planes,
    List<MeasurementPoint>? points,
    bool? isTrackingNormal,
  }) {
    return RoomScanActive(
      planes: planes ?? this.planes,
      points: points ?? this.points,
      isTrackingNormal: isTrackingNormal ?? this.isTrackingNormal,
    );
  }
}

/// Submitting scan data to the backend.
class RoomScanSubmitting extends RoomScanState {}

/// Scan successfully submitted and saved.
class RoomScanSuccess extends RoomScanState {
  final RoomModel room;

  const RoomScanSuccess({required this.room});

  @override
  List<Object?> get props => [room.id];
}

/// An error occurred during scanning or submission.
class RoomScanError extends RoomScanState {
  final String message;

  const RoomScanError({required this.message});

  @override
  List<Object?> get props => [message];
}

