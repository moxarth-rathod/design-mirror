/// DesignMirror AI — Room Scan BLoC Events

import 'package:equatable/equatable.dart';

import '../../models/ar_models.dart';

abstract class RoomScanEvent extends Equatable {
  const RoomScanEvent();

  @override
  List<Object?> get props => [];
}

/// User started a new AR scanning session.
class RoomScanStarted extends RoomScanEvent {}

/// AR engine detected a new plane.
class RoomScanPlaneDetected extends RoomScanEvent {
  final ARPlane plane;

  const RoomScanPlaneDetected({required this.plane});

  @override
  List<Object?> get props => [plane.id];
}

/// User tapped to add a measurement point.
class RoomScanPointAdded extends RoomScanEvent {
  final ARPoint position;
  final String label;

  const RoomScanPointAdded({required this.position, required this.label});

  @override
  List<Object?> get props => [position, label];
}

/// User tapped undo to remove last measurement point.
class RoomScanPointUndone extends RoomScanEvent {}

/// User finished scanning and wants to submit.
class RoomScanSubmitted extends RoomScanEvent {
  final String roomName;

  const RoomScanSubmitted({required this.roomName});

  @override
  List<Object?> get props => [roomName];
}

/// User cancelled the scanning session.
class RoomScanCancelled extends RoomScanEvent {}

