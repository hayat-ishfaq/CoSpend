import 'dart:typed_data';

import '../../../shared/models/app_user.dart';
import 'auth_user.dart';

/// Authentication boundary. UI code depends on this interface instead of the
/// Firebase SDK, so it can be faked in tests.
abstract interface class AuthRepository {
  /// Emits the current Firebase auth state (null when signed out).
  Stream<AuthUser?> authStateChanges();

  Future<AuthUser> signInWithEmail({
    required String email,
    required String password,
  });

  /// Creates the account and provisions the `users/{uid}` profile document.
  Future<AppUser> signUpWithEmail({
    required String name,
    required String email,
    required String password,
  });

  Future<void> sendPasswordReset({required String email});

  Future<void> signOut();

  /// Streams the `users/{uid}` document; emits null when it does not exist.
  Stream<AppUser?> watchCurrentUser(String uid);

  /// Uploads a JPEG avatar to Cloud Storage and returns its download URL.
  Future<String> uploadAvatar({
    required String uid,
    required Uint8List bytes,
  });

  /// Updates user profile details, syncing Auth, users/{uid}, and household members.
  Future<void> updateProfile({
    required String uid,
    required String name,
    String? photoUrl,
    String? phone,
    String? upiId,
    String? bio,
    String? householdId,
  });

  /// Permanently deletes the authenticated user's account and all associated
  /// data (users/{uid} document, household membership). Re-authentication with
  /// [password] is performed first to satisfy Firebase's recent-login requirement.
  Future<void> deleteAccount({
    required String uid,
    required String email,
    required String password,
    String? householdId,
  });
}
