/// DesignMirror AI — Application Configuration
///
/// Central place for all configuration constants.
/// In production, these would be loaded from environment-specific config files.

class AppConfig {
  AppConfig._(); // Private constructor — prevents instantiation

  // ── API ─────────────────────────────────────
  /// Base URL for the FastAPI backend.
  /// Change this when switching between local dev and production.
  // static const String apiBaseUrl = 'http://localhost:8000';
  static const String apiBaseUrl = 'http://192.168.1.10:8000';
  static const String apiVersion = '/api/v1';
  static const String apiUrl = '$apiBaseUrl$apiVersion';

  // ── Timeouts ────────────────────────────────
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 15);

  // ── Auth ────────────────────────────────────
  static const String accessTokenKey = 'access_token';
  static const String refreshTokenKey = 'refresh_token';

  // ── AR Settings ─────────────────────────────
  /// Minimum confidence level for AR plane detection (0.0 to 1.0).
  /// Lower = more planes detected but less accurate.
  /// Higher = fewer planes but more reliable measurements.
  static const double arPlaneConfidenceThreshold = 0.7;

  /// Minimum area (m²) for a detected plane to be considered a valid surface.
  /// Prevents tiny fragments from cluttering the scan.
  static const double arMinPlaneArea = 0.25;

  // ── UI ──────────────────────────────────────
  static const String appName = 'DesignMirror';
  static const String appTagline = 'Design your space with AI';
}

