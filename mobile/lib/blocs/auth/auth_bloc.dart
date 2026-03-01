/// DesignMirror AI — Auth BLoC
///
/// MENTOR MOMENT: What is BLoC?
/// ────────────────────────────
/// BLoC = Business Logic Component. It's a state management pattern:
///
///   UI ──(Event)──▶ BLoC ──(State)──▶ UI
///
/// 1. User taps "Login" → UI sends [AuthLoginRequested] event to the BLoC.
/// 2. BLoC calls the repository, gets tokens, fetches user profile.
/// 3. BLoC emits [AuthAuthenticated] state with the user data.
/// 4. UI rebuilds to show the home screen.
///
/// WHY BLoC instead of Provider/Riverpod?
///   • Strict separation: UI code NEVER contains business logic.
///   • Predictable: Every state transition is traceable via events.
///   • Testable: Feed events in, assert states out — no UI needed.

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';

import '../../repositories/auth_repository.dart';
import 'auth_event.dart';
import 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository _authRepository;
  final Logger _logger = Logger();

  AuthBloc({required AuthRepository authRepository})
      : _authRepository = authRepository,
        super(AuthInitial()) {
    // Register event handlers
    on<AuthCheckRequested>(_onCheckRequested);
    on<AuthLoginRequested>(_onLoginRequested);
    on<AuthSignupRequested>(_onSignupRequested);
    on<AuthLogoutRequested>(_onLogoutRequested);
    on<AuthRefreshProfile>(_onRefreshProfile);
  }

  /// Check if user has a valid session on app startup.
  Future<void> _onCheckRequested(
    AuthCheckRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      final isLoggedIn = await _authRepository.isLoggedIn();
      if (isLoggedIn) {
        // Try to fetch the current user profile
        // If the token is expired, the API interceptor will try to refresh it
        final user = await _authRepository.getCurrentUser();
        emit(AuthAuthenticated(user: user));
        _logger.i('Session restored for ${user.email}');
      } else {
        emit(AuthUnauthenticated());
      }
    } catch (e) {
      _logger.w('Session check failed: $e');
      emit(AuthUnauthenticated());
    }
  }

  /// Handle login form submission.
  Future<void> _onLoginRequested(
    AuthLoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      await _authRepository.login(
        email: event.email,
        password: event.password,
      );
      final user = await _authRepository.getCurrentUser();
      emit(AuthAuthenticated(user: user));
      _logger.i('Login successful: ${event.email}');
    } catch (e) {
      emit(AuthError(message: e.toString()));
      // Emit unauthenticated after error so UI can show login form again
      emit(AuthUnauthenticated());
    }
  }

  /// Handle signup form submission.
  Future<void> _onSignupRequested(
    AuthSignupRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      await _authRepository.signup(
        email: event.email,
        fullName: event.fullName,
        password: event.password,
      );
      // Auto-login after successful signup
      await _authRepository.login(
        email: event.email,
        password: event.password,
      );
      final user = await _authRepository.getCurrentUser();
      emit(AuthAuthenticated(user: user));
      _logger.i('Signup + auto-login successful: ${event.email}');
    } catch (e) {
      emit(AuthError(message: e.toString()));
      emit(AuthUnauthenticated());
    }
  }

  /// Re-fetch user profile after an edit.
  Future<void> _onRefreshProfile(
    AuthRefreshProfile event,
    Emitter<AuthState> emit,
  ) async {
    try {
      final user = await _authRepository.getCurrentUser();
      emit(AuthAuthenticated(user: user));
    } catch (_) {}
  }

  /// Handle logout.
  Future<void> _onLogoutRequested(
    AuthLogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    await _authRepository.logout();
    emit(AuthUnauthenticated());
    _logger.i('User logged out');
  }
}

