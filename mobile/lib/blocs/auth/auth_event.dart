/// DesignMirror AI — Auth BLoC Events
///
/// Events represent user actions or system triggers that the BLoC reacts to.
/// Think of them as "messages" sent to the BLoC.

import 'package:equatable/equatable.dart';

abstract class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

/// Check if the user has a stored session (app startup).
class AuthCheckRequested extends AuthEvent {}

/// User submitted the login form.
class AuthLoginRequested extends AuthEvent {
  final String email;
  final String password;

  const AuthLoginRequested({required this.email, required this.password});

  @override
  List<Object?> get props => [email, password];
}

/// User submitted the signup form.
class AuthSignupRequested extends AuthEvent {
  final String email;
  final String fullName;
  final String password;

  const AuthSignupRequested({
    required this.email,
    required this.fullName,
    required this.password,
  });

  @override
  List<Object?> get props => [email, fullName, password];
}

/// User tapped logout.
class AuthLogoutRequested extends AuthEvent {}

/// Re-fetch the current user profile (after profile edit).
class AuthRefreshProfile extends AuthEvent {}

