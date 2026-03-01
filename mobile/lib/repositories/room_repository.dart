/// DesignMirror AI — Room Repository
///
/// Handles communication with the backend room scan endpoints.
/// Translates AR scan data into API requests and parses responses.

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';

import '../models/ar_models.dart';
import '../models/room_model.dart';
import '../services/api_service.dart';

class RoomRepository {
  final ApiService _api;
  final Logger _logger = Logger();

  RoomRepository({required ApiService apiService}) : _api = apiService;

  /// Submit a room scan to the backend for processing.
  ///
  /// The backend will:
  /// 1. Validate the scan data
  /// 2. Transform AR coordinates into real-world measurements
  /// 3. Optionally trigger SAM segmentation (async via Celery)
  /// 4. Return the saved room with a processing status
  Future<RoomModel> submitScan(RoomScanData scanData) async {
    try {
      _logger.i(
        'Submitting scan "${scanData.roomName}" — '
        '${scanData.planes.length} planes, '
        '${scanData.measurementPoints.length} points',
      );

      final response = await _api.post(
        '/rooms/scan',
        data: scanData.toJson(),
      );

      return RoomModel.fromJson(response.data);
    } on DioException catch (e) {
      throw _extractError(e);
    }
  }

  /// Create a room from manually entered dimensions (no AR scan).
  Future<RoomModel> createManualRoom({
    required String roomName,
    required double widthM,
    required double lengthM,
    double? heightM,
    String? roomType,
  }) async {
    try {
      _logger.i('Creating manual room "$roomName" — ${widthM}×${lengthM}m');

      final body = <String, dynamic>{
        'room_name': roomName,
        'width_m': widthM,
        'length_m': lengthM,
      };
      if (heightM != null) body['height_m'] = heightM;
      if (roomType != null) body['room_type'] = roomType;

      final response = await _api.post('/rooms/manual', data: body);
      return RoomModel.fromJson(response.data);
    } on DioException catch (e) {
      throw _extractError(e);
    }
  }

  Future<RoomModel> updateRoom(String roomId, {String? roomName, String? roomType}) async {
    try {
      final body = <String, dynamic>{};
      if (roomName != null) body['room_name'] = roomName;
      if (roomType != null) body['room_type'] = roomType;
      final response = await _api.patch('/rooms/$roomId', data: body);
      return RoomModel.fromJson(response.data);
    } on DioException catch (e) {
      throw _extractError(e);
    }
  }

  Future<Map<String, dynamic>> getRecommendations(String roomId) async {
    try {
      final response = await _api.get('/catalog/recommendations', queryParams: {'room_id': roomId});
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _extractError(e);
    }
  }

  Future<Map<String, dynamic>> checkMultiFit({
    required String roomId,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      final response = await _api.post('/fitcheck/multi', data: {
        'room_id': roomId,
        'items': items,
      });
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _extractError(e);
    }
  }

  /// Get all room scans for the current user.
  Future<List<RoomModel>> getUserRooms() async {
    try {
      final response = await _api.get('/rooms');
      final rooms = (response.data as List<dynamic>)
          .map((json) => RoomModel.fromJson(json as Map<String, dynamic>))
          .toList();
      return rooms;
    } on DioException catch (e) {
      throw _extractError(e);
    }
  }

  /// Get a specific room scan by ID.
  Future<RoomModel> getRoom(String roomId) async {
    try {
      final response = await _api.get('/rooms/$roomId');
      return RoomModel.fromJson(response.data);
    } on DioException catch (e) {
      throw _extractError(e);
    }
  }

  /// Get rooms as raw JSON maps (lightweight, for pickers/dropdowns).
  Future<List<Map<String, dynamic>>> getRooms() async {
    try {
      final response = await _api.get('/rooms');
      return (response.data as List<dynamic>)
          .map((e) => e as Map<String, dynamic>)
          .toList();
    } on DioException catch (e) {
      throw _extractError(e);
    }
  }

  /// Upload a photo for a room.
  Future<Map<String, dynamic>> uploadPhoto(String roomId, String filePath) async {
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath),
      });
      final response = await _api.post('/rooms/$roomId/photos', data: formData);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _extractError(e);
    }
  }

  /// Delete a photo from a room.
  Future<void> deletePhoto(String roomId, int photoIndex) async {
    try {
      await _api.delete('/rooms/$roomId/photos/$photoIndex');
    } on DioException catch (e) {
      throw _extractError(e);
    }
  }

  /// Delete a room scan.
  Future<void> deleteRoom(String roomId) async {
    try {
      await _api.delete('/rooms/$roomId');
      _logger.i('Room $roomId deleted');
    } on DioException catch (e) {
      throw _extractError(e);
    }
  }

  String _extractError(DioException e) {
    if (e.response?.data != null && e.response!.data is Map) {
      final detail = e.response!.data['detail'];
      if (detail != null) return detail.toString();
    }
    if (e.type == DioExceptionType.connectionTimeout) {
      return 'Connection timed out. Please check your internet.';
    }
    return 'Something went wrong. Please try again.';
  }
}

