/// DesignMirror AI — Auth BLoC States
///
/// States represent the current condition of the auth flow.
/// The UI rebuilds whenever the state changes.
///
/// MENTOR MOMENT: Why Equatable?
/// ────────────────────────────
/// BLoC only rebuilds the UI when the state actually CHANGES.
/// It compares the old state to the new state using ==.
/// Without Equatable, Dart compares object IDENTITY (is it the same instance?).
/// With Equatable, Dart compares object VALUE (do the fields match?).
/// This prevents unnecessary UI rebuilds.

import 'package:equatable/equatable.dart';

import '../../models/user_model.dart';

abstract class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

/// Initial state — haven't checked auth status yet.
class AuthInitial extends AuthState {}

/// Currently checking stored tokens / loading user profile.
class AuthLoading extends AuthState {}

/// User is authenticated. Contains the user profile.
class AuthAuthenticated extends AuthState {
  final UserModel user;

  const AuthAuthenticated({required this.user});

  @override
  List<Object?> get props => [user.id];
}

/// User is not authenticated (no tokens or tokens expired).
class AuthUnauthenticated extends AuthState {}

/// Auth operation failed. Contains the error message for the UI.
class AuthError extends AuthState {
  final String message;

  const AuthError({required this.message});

  @override
  List<Object?> get props => [message];
}

