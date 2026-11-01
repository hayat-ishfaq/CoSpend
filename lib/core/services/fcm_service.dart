import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'notification_service.dart';

/// Top-level handler executed when a push notification arrives while the app
/// is in the BACKGROUND or TERMINATED state.
///
/// Must be a top-level function (not a class method) as required by FCM.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase.initializeApp() is NOT needed here because firebase_messaging
  // ensures the native SDK is initialized before invoking this handler.
  final notification = message.notification;
  if (notification == null) return;

  await NotificationService.instance.showNotification(
    notificationId: (message.data['notificationId'] as String?) ?? message.messageId ?? message.sentTime.toString(),
    title: notification.title ?? 'CoSpend',
    body: notification.body ?? '',
    payload: message.data['route'] as String?,
  );
}

/// Service wrapping Firebase Cloud Messaging for CoSpend.
///
/// Responsibilities:
/// - Registers background message handler.
/// - Requests notification permission on first launch.
/// - Retrieves the FCM device token for server-side targeting.
/// - Handles foreground messages and tap actions.
class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  FirebaseMessaging? _messagingInstance;
  FirebaseMessaging? get _messaging {
    try {
      return _messagingInstance ??= FirebaseMessaging.instance;
    } catch (e) {
      debugPrint('[FCM] FirebaseMessaging unavailable: $e');
      return null;
    }
  }

  /// Call once from [main()] after Firebase.initializeApp().
  Future<void> initialize() async {
    final messaging = _messaging;
    if (messaging == null) return;

    // Register the background handler (must be called before runApp).
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Request permission (Android 13+ / iOS).
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    debugPrint(
      '[FCM] Permission status: ${settings.authorizationStatus}',
    );

    // Subscribe to the global household topic for broadcast messages.
    // Individual household topics are subscribed when a household is joined.
    await messaging.subscribeToTopic('cospend_global');

    // Handle notification taps when app is in the BACKGROUND (not killed).
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);

    // Handle notification taps from TERMINATED state.
    final initial = await messaging.getInitialMessage();
    if (initial != null) _handleMessage(initial);

    // Handle messages while app is in FOREGROUND — show local notification.
    FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if (notification == null) return;
      NotificationService.instance.showNotification(
        notificationId: (message.data['notificationId'] as String?) ?? message.messageId ?? message.sentTime?.toString() ?? 'fcm_msg',
        title: notification.title ?? 'CoSpend',
        body: notification.body ?? '',
        payload: message.data['route'] as String?,
      );
    });
  }

  /// Retrieves the FCM registration token for this device.
  ///
  /// Store this on the user's Firestore document to enable targeted pushes.
  Future<String?> getToken() async {
    try {
      return await _messaging?.getToken();
    } catch (e) {
      debugPrint('[FCM] Failed to get token: $e');
      return null;
    }
  }

  /// Subscribe to a household-specific topic so all household members receive
  /// broadcast push notifications without maintaining a token list.
  Future<void> subscribeToHousehold(String householdId) async {
    try {
      await _messaging?.subscribeToTopic('household_$householdId');
      debugPrint('[FCM] Subscribed to household_$householdId');
    } catch (e) {
      debugPrint('[FCM] Failed to subscribe to household: $e');
    }
  }

  /// Unsubscribe when a user leaves a household.
  Future<void> unsubscribeFromHousehold(String householdId) async {
    try {
      await _messaging?.unsubscribeFromTopic('household_$householdId');
      debugPrint('[FCM] Unsubscribed from household_$householdId');
    } catch (e) {
      debugPrint('[FCM] Failed to unsubscribe from household: $e');
    }
  }

  void _handleMessage(RemoteMessage message) {
    // TODO: navigate to the relevant screen based on message.data['route'].
    debugPrint('[FCM] Notification tapped: ${message.data}');
  }
}
