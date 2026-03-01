/// DesignMirror AI — App Routes
///
/// Uses go_router for declarative, URL-based routing.
/// This approach makes deep-linking and navigation guards straightforward.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../screens/auth/login_screen.dart';
import '../screens/auth/signup_screen.dart';
import '../screens/budget/budget_screen.dart';
import '../screens/catalog/catalog_screen.dart';
import '../screens/history/history_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/rooms/rooms_screen.dart';
import '../screens/ar/ar_preview_screen.dart';
import '../screens/layout/layout_planner_screen.dart';
import '../screens/recommendations/recommendations_screen.dart';
import '../screens/scanner/ar_scanner_screen.dart';
import '../screens/scanner/manual_room_screen.dart';
import '../screens/scanner/scanner_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/wishlist/wishlist_screen.dart';

class AppRoutes {
  AppRoutes._();

  static const String login = '/login';
  static const String signup = '/signup';
  static const String home = '/';
  static const String rooms = '/rooms';
  static const String scanner = '/scanner';
  static const String arScanner = '/ar-scanner';
  static const String manualRoom = '/manual-room';
  static const String catalog = '/catalog';
  static const String settings = '/settings';
  static const String wishlist = '/wishlist';
  static const String history = '/history';
  static const String budget = '/budget';
  static const String layoutPlanner = '/layout-planner';
  static const String recommendations = '/recommendations';
  static const String arPreview = '/ar-preview';

  /// The main router configuration.
  ///
  /// [isAuthenticated] determines which screen the user starts on.
  /// If not logged in → /login. If logged in → / (home).
  static GoRouter router({required bool isAuthenticated}) {
    return GoRouter(
      initialLocation: isAuthenticated ? home : login,
      routes: [
        // ── Auth Routes ───────────────────────
        GoRoute(
          path: login,
          name: 'login',
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: signup,
          name: 'signup',
          builder: (context, state) => const SignupScreen(),
        ),

        // ── Main App Routes ───────────────────
        GoRoute(
          path: home,
          name: 'home',
          builder: (context, state) => const HomeScreen(),
        ),
        GoRoute(
          path: rooms,
          name: 'rooms',
          builder: (context, state) => const RoomsScreen(),
        ),
        GoRoute(
          path: scanner,
          name: 'scanner',
          builder: (context, state) => const ScannerScreen(),
        ),
        GoRoute(
          path: arScanner,
          name: 'arScanner',
          builder: (context, state) => const ARScannerScreen(),
        ),
        GoRoute(
          path: manualRoom,
          name: 'manualRoom',
          builder: (context, state) => const ManualRoomScreen(),
        ),
        GoRoute(
          path: catalog,
          name: 'catalog',
          builder: (context, state) => const CatalogScreen(),
        ),
        GoRoute(
          path: settings,
          name: 'settings',
          builder: (context, state) => const SettingsScreen(),
        ),
        GoRoute(
          path: wishlist,
          name: 'wishlist',
          builder: (context, state) => const WishlistScreen(),
        ),
        GoRoute(
          path: history,
          name: 'history',
          builder: (context, state) => const HistoryScreen(),
        ),
        GoRoute(
          path: budget,
          name: 'budget',
          builder: (context, state) => const BudgetScreen(),
        ),
        GoRoute(
          path: layoutPlanner,
          name: 'layoutPlanner',
          builder: (context, state) => const LayoutPlannerScreen(),
        ),
        GoRoute(
          path: recommendations,
          name: 'recommendations',
          builder: (context, state) => const RecommendationsScreen(),
        ),
        GoRoute(
          path: arPreview,
          name: 'arPreview',
          builder: (context, state) => ARPreviewScreen.fromRoute(state),
        ),
      ],

      // ── Navigation Guard ────────────────────
      redirect: (BuildContext context, GoRouterState state) {
        final loggingIn = state.matchedLocation == login ||
            state.matchedLocation == signup;

        // Not authenticated? Force to login (unless already there)
        if (!isAuthenticated && !loggingIn) {
          return login;
        }

        // Authenticated but on login page? Go to home
        if (isAuthenticated && loggingIn) {
          return home;
        }

        return null; // No redirect needed
      },
    );
  }
}

