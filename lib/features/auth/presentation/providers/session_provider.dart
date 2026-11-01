import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/firestore_constants.dart';
import '../../../../core/services/fcm_service.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../firebase_options.dart';
import '../../../../shared/models/app_user.dart';
import '../../domain/session_state.dart';
import 'auth_providers.dart';

/// Asynchronous bootstrap for Firebase, notification channels, and FCM.
///
/// Running this inside a provider instead of blocking main() allows the app
/// to mount and display the splash screen immediately on frame 1 without delay.
final firebaseInitProvider = FutureProvider<void>((ref) async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase.initializeApp warning: $e');
  }

  // Enable Crashlytics in release mode only.
  if (!kDebugMode) {
    await FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(true);
    FlutterError.onError =
        FirebaseCrashlytics.instance.recordFlutterFatalError;
  }

  // Initialize local notification tray (foreground alerts via Firestore).
  await NotificationService.instance.initialize().catchError((e) {
    debugPrint('Failed to initialize NotificationService: $e');
  });

  // Initialize Firebase Cloud Messaging (background & push notifications).
  FcmService.instance.initialize().catchError((e) {
    debugPrint('Failed to initialize FcmService: $e');
  });
});

/// Resolves where the user is in the app (signed out / needs household /
/// ready). Every router redirect reads this provider.
class SessionController extends AsyncNotifier<SessionState> {
  @override
  Future<SessionState> build() async {
    // Ensure Firebase is initialized before accessing FirebaseAuth / Firestore
    try {
      await ref.watch(firebaseInitProvider.future);
    } catch (_) {}

    final authUser = await ref.watch(authStateProvider.future);
    if (authUser == null) return const SessionSignedOut();

    AppUser? appUser = await ref.watch(currentUserProvider.future);
    if (appUser == null) {
      // Auto-heal missing profile document for authenticated user:
      final fallbackName = authUser.displayName?.trim().isNotEmpty == true
          ? authUser.displayName!.trim()
          : (authUser.email.contains('@')
              ? authUser.email.split('@').first
              : 'User');
      final fallbackUser = AppUser(
        id: authUser.uid,
        name: fallbackName,
        email: authUser.email,
        createdAt: DateTime.now(),
      );

      // Attempt to heal Firestore document in the background
      try {
        await FirebaseFirestore.instance
            .collection(FirestoreCollections.users)
            .doc(authUser.uid)
            .set(fallbackUser.toMap(), SetOptions(merge: true));
        appUser = fallbackUser;
      } catch (e) {
        debugPrint('Auto-heal profile document: $e');
        appUser = fallbackUser;
      }
    }

    if (appUser.householdId == null) {
      return SessionNeedsHousehold(user: appUser);
    }
    return SessionReady(user: appUser);
  }
}

final sessionProvider =
    AsyncNotifierProvider<SessionController, SessionState>(
  SessionController.new,
);

/// Tracks whether the animated Lottie splash animation has completed.
///
/// Driven directly by the animation controller completing its forward pass,
/// eliminating hardcoded timers.
class SplashAnimationController extends Notifier<bool> {
  @override
  bool build() => false;

  void complete() => state = true;
}

final splashAnimationCompletedProvider =
    NotifierProvider<SplashAnimationController, bool>(
  SplashAnimationController.new,
);
