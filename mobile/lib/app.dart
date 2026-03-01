/// DesignMirror AI — Root App Widget
///
/// Sets up BLoC providers, theme, and routing.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'blocs/auth/auth_bloc.dart';
import 'blocs/auth/auth_event.dart';
import 'blocs/auth/auth_state.dart';
import 'blocs/catalog/catalog_bloc.dart';
import 'blocs/room_scan/room_scan_bloc.dart';
import 'config/routes.dart';
import 'config/theme.dart';
import 'repositories/room_repository.dart';
import 'screens/splash/splash_screen.dart';
import 'services/ar_service.dart';
import 'services/preferences_service.dart';
import 'services/service_locator.dart';

class DesignMirrorApp extends StatefulWidget {
  const DesignMirrorApp({super.key});

  @override
  State<DesignMirrorApp> createState() => _DesignMirrorAppState();
}

class _DesignMirrorAppState extends State<DesignMirrorApp> {
  GoRouter? _router;
  bool? _lastAuth;

  GoRouter _getRouter(bool isAuthenticated) {
    if (_router == null || _lastAuth != isAuthenticated) {
      _lastAuth = isAuthenticated;
      _router = AppRoutes.router(isAuthenticated: isAuthenticated);
    }
    return _router!;
  }

  @override
  Widget build(BuildContext context) {
    final prefs = getIt<PreferencesService>();

    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>(
          create: (_) => getIt<AuthBloc>()..add(AuthCheckRequested()),
        ),
        BlocProvider<RoomScanBloc>(
          create: (_) => RoomScanBloc(
            arService: getIt<ARService>(),
            roomRepository: getIt<RoomRepository>(),
          ),
        ),
        BlocProvider<CatalogBloc>(
          create: (_) => getIt<CatalogBloc>(),
        ),
      ],
      child: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, authState) {
          final isChecking = authState is AuthInitial;
          final isAuthenticated = authState is AuthAuthenticated;
          final router = _getRouter(isAuthenticated);

          return ValueListenableBuilder<ThemeMode>(
            valueListenable: prefs.themeMode,
            builder: (context, themeMode, _) {
              if (isChecking) {
                return MaterialApp(
                  title: 'DesignMirror',
                  debugShowCheckedModeBanner: false,
                  theme: AppTheme.lightTheme,
                  darkTheme: AppTheme.darkTheme,
                  themeMode: themeMode,
                  home: const SplashScreen(),
                );
              }

              return MaterialApp.router(
                title: 'DesignMirror',
                debugShowCheckedModeBanner: false,
                theme: AppTheme.lightTheme,
                darkTheme: AppTheme.darkTheme,
                themeMode: themeMode,
                routerConfig: router,
              );
            },
          );
        },
      ),
    );
  }
}

