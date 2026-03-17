import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/google_sign_in_config.dart';
import 'session_provider.dart';
import 'deck_provider.dart';

/// User auth state.
enum AuthStatus {
  unknown,
  unauthenticated,
  authenticated,
}

/// Authenticated user info.
class AuthenticatedUser {
  const AuthenticatedUser({
    required this.uid,
    required this.email,
    this.displayName,
    this.photoUrl,
  });

  final String uid;
  final String? email;
  final String? displayName;
  final String? photoUrl;

  factory AuthenticatedUser.fromFirebaseUser(User user) {
    return AuthenticatedUser(
      uid: user.uid,
      email: user.email,
      displayName: user.displayName,
      photoUrl: user.photoURL,
    );
  }
}

/// Auth state: status + optional user.
class AuthState {
  const AuthState({
    required this.status,
    this.user,
    this.error,
  });

  final AuthStatus status;
  final AuthenticatedUser? user;
  final String? error;

  bool get isAuthenticated => status == AuthStatus.authenticated && user != null;

  AuthState copyWith({
    AuthStatus? status,
    AuthenticatedUser? user,
    String? error,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      error: error,
    );
  }

  static const initial = AuthState(status: AuthStatus.unknown);
}

/// Auth notifier: manages Firebase Auth state and session linking.
class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._ref) : super(AuthState.initial) {
    _init();
  }

  final Ref _ref;
  StreamSubscription<User?>? _authSubscription;

  void _init() {
    // Listen to Firebase Auth state changes
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        state = AuthState(
          status: AuthStatus.authenticated,
          user: AuthenticatedUser.fromFirebaseUser(user),
        );
        // Link session to user after auth
        _linkSessionToUser();
      } else {
        state = const AuthState(status: AuthStatus.unauthenticated);
      }
    });
  }

  /// Get current Firebase ID token for API calls.
  Future<String?> getIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return await user.getIdToken();
  }

  /// Link the current anonymous session to the authenticated user.
  Future<void> _linkSessionToUser() async {
    final sessionId = _ref.read(sessionIdProvider);
    if (sessionId == null || sessionId.isEmpty) return;

    final token = await getIdToken();
    if (token == null) return;

    try {
      final client = _ref.read(apiClientProvider);
      await client.linkSession(token: token, sessionId: sessionId);
    } catch (e) {
      // Ignore errors - session linking is best-effort
      print('Failed to link session: $e');
    }
  }

  /// Sign up with email and password.
  Future<void> signUpWithEmail(String email, String password) async {
    state = state.copyWith(status: AuthStatus.unknown, error: null);
    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        error: _getAuthErrorMessage(e.code),
      );
      rethrow;
    }
  }

  /// Sign in with email and password.
  Future<void> signInWithEmail(String email, String password) async {
    state = state.copyWith(status: AuthStatus.unknown, error: null);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        error: _getAuthErrorMessage(e.code),
      );
      rethrow;
    }
  }

  /// Sign in with Google.
  Future<void> signInWithGoogle() async {
    state = state.copyWith(status: AuthStatus.unknown, error: null);
    try {
      final googleSignIn = GoogleSignIn(
        clientId: hasGoogleSignInWebClientId ? kGoogleSignInWebClientId : null,
        scopes: ['email', 'profile'],
      );
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        state = state.copyWith(status: AuthStatus.unauthenticated);
        return;
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        error: _getAuthErrorMessage(e.code),
      );
      rethrow;
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        error: 'Google sign-in failed. Please try again.',
      );
      rethrow;
    }
  }

  /// Sign out.
  Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
    await GoogleSignIn().signOut();
  }

  /// Send password reset email.
  Future<void> sendPasswordResetEmail(String email) async {
    await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
  }

  String _getAuthErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'invalid-email':
        return 'Invalid email address.';
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'operation-not-allowed':
        return 'This sign-in method is not enabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      default:
        return 'Authentication failed. Please try again.';
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}

/// Provider for auth state.
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref);
});

/// Convenience provider for checking if user is authenticated.
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).isAuthenticated;
});

/// Convenience provider for current user.
final currentUserProvider = Provider<AuthenticatedUser?>((ref) {
  return ref.watch(authProvider).user;
});
