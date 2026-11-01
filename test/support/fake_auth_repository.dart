import 'dart:async';
import 'dart:typed_data';

import 'package:expensetrack/features/auth/domain/auth_repository.dart';
import 'package:expensetrack/features/auth/domain/auth_user.dart';
import 'package:expensetrack/shared/models/app_user.dart';

/// In-memory [AuthRepository] for widget and unit tests. No Firebase involved.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.currentUser, this.appUser});

  /// Current auth identity (emit changes via [emitAuthState]).
  AuthUser? currentUser;

  /// Current profile document.
  AppUser? appUser;

  final StreamController<AuthUser?> _authChanges =
      StreamController<AuthUser?>.broadcast();

  @override
  Stream<AuthUser?> authStateChanges() async* {
    yield currentUser;
    yield* _authChanges.stream;
  }

  @override
  Stream<AppUser?> watchCurrentUser(String uid) async* {
    yield appUser;
  }

  /// Pushes a new auth state to listeners and updates [currentUser].
  void emitAuthState(AuthUser? user) {
    currentUser = user;
    _authChanges.add(user);
  }

  @override
  Future<AuthUser> signInWithEmail({
    required String email,
    required String password,
  }) =>
      throw UnimplementedError('Not exercised in widget tests.');

  @override
  Future<AppUser> signUpWithEmail({
    required String name,
    required String email,
    required String password,
  }) =>
      throw UnimplementedError('Not exercised in widget tests.');

  @override
  Future<void> sendPasswordReset({required String email}) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<String> uploadAvatar({
    required String uid,
    required Uint8List bytes,
  }) async {
    return 'https://example.com/avatars/$uid.jpg';
  }

  @override
  Future<void> updateProfile({
    required String uid,
    required String name,
    String? photoUrl,
    String? phone,
    String? upiId,
    String? bio,
    String? householdId,
  }) async {
    if (appUser != null && appUser!.id == uid) {
      appUser = appUser!.copyWith(
        name: name,
        photoUrl: photoUrl,
        phone: phone,
        upiId: upiId,
        bio: bio,
      );
    }
  }

  @override
  Future<void> deleteAccount({
    required String uid,
    required String email,
    required String password,
    String? householdId,
  }) async {
    currentUser = null;
    appUser = null;
    _authChanges.add(null);
  }
}