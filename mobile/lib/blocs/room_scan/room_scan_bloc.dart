/// DesignMirror AI — Room Scan BLoC
///
/// Manages the state of an AR scanning session.
/// Coordinates between the AR service (hardware) and the room repository (backend).

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';

import '../../models/ar_models.dart';
import '../../repositories/room_repository.dart';
import '../../services/ar_service.dart';
import 'room_scan_event.dart';
import 'room_scan_state.dart';

class RoomScanBloc extends Bloc<RoomScanEvent, RoomScanState> {
  final ARService _arService;
  final RoomRepository _roomRepository;
  final Logger _logger = Logger();

  RoomScanBloc({
    required ARService arService,
    required RoomRepository roomRepository,
  })  : _arService = arService,
        _roomRepository = roomRepository,
        super(RoomScanInitial()) {
    on<RoomScanStarted>(_onStarted);
    on<RoomScanPlaneDetected>(_onPlaneDetected);
    on<RoomScanPointAdded>(_onPointAdded);
    on<RoomScanPointUndone>(_onPointUndone);
    on<RoomScanSubmitted>(_onSubmitted);
    on<RoomScanCancelled>(_onCancelled);
  }

  /// Start the AR scanning session.
  Future<void> _onStarted(
    RoomScanStarted event,
    Emitter<RoomScanState> emit,
  ) async {
    emit(RoomScanInitializing());

    try {
      await _arService.startSession();

      if (_arService.state == ARSessionState.notAvailable) {
        emit(const RoomScanError(
          message: 'AR is not available on this device. '
              'Please use a device with ARKit (iOS) or ARCore (Android) support.',
        ));
        return;
      }

      emit(const RoomScanActive(planes: [], points: []));

      // Listen to plane detection stream
      _arService.planesStream.listen((planes) {
        if (state is RoomScanActive) {
          add(RoomScanPlaneDetected(plane: planes.last));
        }
      });

      _logger.i('Room scan session started');
    } catch (e) {
      emit(RoomScanError(message: 'Failed to start AR: $e'));
    }
  }

  /// Handle newly detected plane.
  void _onPlaneDetected(
    RoomScanPlaneDetected event,
    Emitter<RoomScanState> emit,
  ) {
    if (state is RoomScanActive) {
      final current = state as RoomScanActive;
      emit(current.copyWith(planes: _arService.detectedPlanes));
    }
  }

  /// Handle user adding a measurement point.
  void _onPointAdded(
    RoomScanPointAdded event,
    Emitter<RoomScanState> emit,
  ) {
    _arService.addMeasurementPoint(event.position, event.label);
    if (state is RoomScanActive) {
      final current = state as RoomScanActive;
      emit(current.copyWith(points: _arService.measurementPoints));
    }
  }

  /// Handle undo of last measurement point.
  void _onPointUndone(
    RoomScanPointUndone event,
    Emitter<RoomScanState> emit,
  ) {
    _arService.undoLastPoint();
    if (state is RoomScanActive) {
      final current = state as RoomScanActive;
      emit(current.copyWith(points: _arService.measurementPoints));
    }
  }

  /// Submit the scan data to the backend.
  Future<void> _onSubmitted(
    RoomScanSubmitted event,
    Emitter<RoomScanState> emit,
  ) async {
    emit(RoomScanSubmitting());

    try {
      // Build the scan data from the AR service
      final scanData = _arService.buildScanData(event.roomName);

      _logger.i(
        'Submitting scan: ${scanData.planes.length} planes, '
        '${scanData.measurementPoints.length} points',
      );

      // Send to backend
      final room = await _roomRepository.submitScan(scanData);

      // Stop AR session
      await _arService.stopSession();

      emit(RoomScanSuccess(room: room));
      _logger.i('Scan submitted successfully — room ID: ${room.id}');
    } catch (e) {
      emit(RoomScanError(message: e.toString()));
    }
  }

  /// Cancel the scanning session.
  Future<void> _onCancelled(
    RoomScanCancelled event,
    Emitter<RoomScanState> emit,
  ) async {
    await _arService.stopSession();
    emit(RoomScanInitial());
    _logger.i('Room scan cancelled');
  }

  @override
  Future<void> close() {
    _arService.dispose();
    return super.close();
  }
}

