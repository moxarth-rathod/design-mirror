/// DesignMirror AI — Service Locator (Dependency Injection)
///
/// PATTERN: Service Locator
/// ────────────────────────
/// Uses GetIt to register all services, repositories, and BLoCs as singletons.
/// Any part of the app can access them via `getIt<ApiService>()`.
///
/// This is configured ONCE at app startup, before any widget is built.

import 'package:get_it/get_it.dart';

import '../blocs/auth/auth_bloc.dart';
import '../blocs/catalog/catalog_bloc.dart';
import '../repositories/auth_repository.dart';
import '../repositories/catalog_repository.dart';
import '../repositories/room_repository.dart';
import '../repositories/wishlist_repository.dart';
import '../services/api_service.dart';
import '../services/ar_service.dart';
import '../services/preferences_service.dart';

final getIt = GetIt.instance;

/// Register all dependencies. Called once in main.dart.
void setupServiceLocator() {
  // ── Services (singletons) ───────────────────
  getIt.registerLazySingleton<ApiService>(() => ApiService());
  getIt.registerLazySingleton<ARService>(() => ARService());
  getIt.registerLazySingleton<PreferencesService>(() => PreferencesService());

  // ── Repositories ────────────────────────────
  getIt.registerLazySingleton<AuthRepository>(
    () => AuthRepository(apiService: getIt<ApiService>()),
  );
  getIt.registerLazySingleton<RoomRepository>(
    () => RoomRepository(apiService: getIt<ApiService>()),
  );
  getIt.registerLazySingleton<CatalogRepository>(
    () => CatalogRepository(apiService: getIt<ApiService>()),
  );
  getIt.registerLazySingleton<WishlistRepository>(
    () => WishlistRepository(apiService: getIt<ApiService>()),
  );

  // ── BLoCs ───────────────────────────────────
  getIt.registerFactory<AuthBloc>(
    () => AuthBloc(authRepository: getIt<AuthRepository>()),
  );
  getIt.registerFactory<CatalogBloc>(
    () => CatalogBloc(catalogRepository: getIt<CatalogRepository>()),
  );
}

