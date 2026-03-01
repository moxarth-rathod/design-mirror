/// DesignMirror AI — Application Entry Point
///
/// This is where the Flutter app starts. It:
/// 1. Initializes Flutter bindings (required before any async work)
/// 2. Sets up the service locator (dependency injection)
/// 3. Launches the root widget

import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'app.dart';
import 'services/preferences_service.dart';
import 'services/service_locator.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  setupServiceLocator();

  await getIt<PreferencesService>().load();

  runApp(const DesignMirrorApp());
}

