import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../../../core/constants/firestore_constants.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/errors/firebase_error_mapper.dart';
import '../../../shared/models/app_user.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_user.dart';

/// Firestore + Firebase Auth implementation of [AuthRepository].
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(
    this._auth,
    this._firestore, [
    FirebaseStorage? storage,
  ]) : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  static AuthUser _toAuthUser(User user) => AuthUser(
        uid: user.uid,
        email: user.email ?? '',
        displayName: user.displayName,
        photoUrl: user.photoURL,
      );

  @override
  Stream<AuthUser?> authStateChanges() => _auth
      .authStateChanges()
      .map((user) => user == null ? null : _toAuthUser(user));

  @override
  Future<AuthUser> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return _toAuthUser(credential.user!);
    } catch (error) {
      throw toAppException(error);
    }
  }

  @override
  Future<AppUser> signUpWithEmail({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user!;
      try {
        await user.updateDisplayName(name.trim());
      } catch (_) {}

      final now = DateTime.now();
      final appUser = AppUser(
        id: user.uid,
        name: name.trim(),
        email: email.trim().toLowerCase(),
        createdAt: now,
      );

      await _firestore
          .collection(FirestoreCollections.users)
          .doc(user.uid)
          .set(appUser.toMap());

      return appUser;
    } catch (error) {
      throw toAppException(error);
    }
  }

  @override
  Future<void> sendPasswordReset({required String email}) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } catch (error) {
      throw toAppException(error);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (error) {
      throw toAppException(error);
    }
  }

  @override
  Future<String> uploadAvatar({
    required String uid,
    required Uint8List bytes,
  }) async {
    try {
      final ref = _storage.ref().child('avatars/$uid/profile.jpg');
      await ref
          .putData(
            bytes,
            SettableMetadata(contentType: 'image/jpeg'),
          )
          .timeout(const Duration(seconds: 8));
      return await ref.getDownloadURL();
    } catch (error) {
      debugPrint('Cloud storage upload warning: $error. Falling back to inline base64 data URI.');
      try {
        final base64String = base64Encode(bytes);
        return 'data:image/jpeg;base64,$base64String';
      } catch (encodeError) {
        throw toAppException(error);
      }
    }
  }

  @override
  Stream<AppUser?> watchCurrentUser(String uid) => _firestore
      .collection(FirestoreCollections.users)
      .doc(uid)
      .snapshots()
      .map((snapshot) =>
          snapshot.exists ? AppUser.fromMap(uid, snapshot.data()!) : null);

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
    try {
      final trimmedName = name.trim();
      final user = _auth.currentUser;
      if (user != null) {
        try {
          await user.updateDisplayName(trimmedName);
          if (photoUrl != null && photoUrl.startsWith('http')) {
            await user.updatePhotoURL(photoUrl);
          } else if (photoUrl == null || photoUrl.isEmpty) {
            await user.updatePhotoURL(null);
          }
        } catch (_) {}
      }

      final userUpdates = <String, dynamic>{
        'name': trimmedName,
        'photoUrl': photoUrl,
        'phone': phone?.trim(),
        'upiId': upiId?.trim(),
        'bio': bio?.trim(),
      };

      await _firestore
          .collection(FirestoreCollections.users)
          .doc(uid)
          .set(userUpdates, SetOptions(merge: true));

      if (householdId != null && householdId.isNotEmpty) {
        try {
          final memberUpdates = <String, dynamic>{
            'name': trimmedName,
            'photoUrl': photoUrl,
            if (phone != null) 'phone': phone.trim(),
            if (upiId != null) 'upiId': upiId.trim(),
          };
          await _firestore
              .collection(FirestoreCollections.households)
              .doc(householdId)
              .collection(FirestoreCollections.members)
              .doc(uid)
              .set(memberUpdates, SetOptions(merge: true));
        } catch (_) {
          // Member document update failure is non-fatal if user left or doc doesn't exist
        }
      }
    } catch (error) {
      throw toAppException(error);
    }
  }

  @override
  Future<void> deleteAccount({
    required String uid,
    required String email,
    required String password,
    String? householdId,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw const AuthException('No authenticated user found.');

      // Re-authenticate to satisfy Firebase recent-login requirement.
      final credential = EmailAuthProvider.credential(
        email: email,
        password: password,
      );
      await user.reauthenticateWithCredential(credential);

      // Remove household membership if the user belongs to one.
      if (householdId != null && householdId.isNotEmpty) {
        try {
          await _firestore
              .collection(FirestoreCollections.households)
              .doc(householdId)
              .collection(FirestoreCollections.members)
              .doc(uid)
              .delete();
        } catch (_) {
          // Non-fatal: proceed even if membership removal fails.
        }
      }

      // Delete the Firestore profile document.
      try {
        await _firestore
            .collection(FirestoreCollections.users)
            .doc(uid)
            .delete();
      } catch (_) {}

      // Delete the Firebase Auth account (point of no return).
      await user.delete();
    } catch (error) {
      throw toAppException(error);
    }
  }
}
