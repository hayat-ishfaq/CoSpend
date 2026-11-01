import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/firestore_constants.dart';
import '../../../../core/services/notification_service.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../auth/presentation/providers/session_provider.dart';
import '../../domain/household_notification.dart';
import 'household_providers.dart';

/// Stream of recent notifications for the active household.
final householdNotificationsProvider =
    StreamProvider<List<HouseholdNotification>>((ref) {
  final household = ref.watch(currentHouseholdProvider).value;
  if (household == null) return Stream.value(const []);

  final firestore = FirebaseFirestore.instance;
  return firestore
      .collection(FirestoreCollections.households)
      .doc(household.id)
      .collection('notifications')
      .orderBy('createdAt', descending: true)
      .limit(30)
      .snapshots()
      .map((snapshot) {
    return snapshot.docs
        .map((doc) => HouseholdNotification.fromMap(doc.id, doc.data()))
        .toList();
  });
});

class LocallyReadNotificationsController extends Notifier<Set<String>> {
  static const String _prefKey = 'cospend_locally_read_notification_ids';
  static final Set<String> _cachedIds = <String>{};

  @override
  Set<String> build() {
    _loadFromPrefs();
    return Set<String>.from(_cachedIds);
  }

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList(_prefKey) ?? [];
      if (stored.isNotEmpty) {
        _cachedIds.addAll(stored);
        state = {...state, ..._cachedIds};
      }
    } catch (_) {}
  }

  void markIds(Iterable<String> ids) {
    _cachedIds.addAll(ids);
    state = {...state, ...ids};
    _saveToPrefs();
  }

  void markOne(String id) {
    _cachedIds.add(id);
    state = {...state, id};
    _saveToPrefs();
  }

  Future<void> _saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefKey, _cachedIds.toList());
    } catch (_) {}
  }
}

/// Tracks notification IDs that have been viewed by the user in this session,
/// clearing the red badge popup immediately without waiting for network latency.
final locallyReadNotificationIdsProvider =
    NotifierProvider<LocallyReadNotificationsController, Set<String>>(
  LocallyReadNotificationsController.new,
);

class NotificationActions extends AsyncNotifier<void> {
  @override
  void build() {}

  /// Mark all notifications as read both locally (instant badge disappearance)
  /// and remotely in Firestore.
  Future<void> markAllAsRead() async {
    final householdId = ref.read(currentHouseholdProvider).value?.id ??
        ref.read(sessionProvider).value?.householdId;
    final authUid = FirebaseAuth.instance.currentUser?.uid;
    final uid = (authUid != null && authUid.isNotEmpty)
        ? authUid
        : (ref.read(sessionProvider).value?.user?.id ??
            ref.read(currentUserProvider).value?.id);
    if (householdId == null || uid == null) return;

    final firestore = FirebaseFirestore.instance;

    // 1. Instant local badge clearance
    final currentNotifs = ref.read(householdNotificationsProvider).value;
    if (currentNotifs != null && currentNotifs.isNotEmpty) {
      final ids = currentNotifs.map((n) => n.id);
      ref.read(locallyReadNotificationIdsProvider.notifier).markIds(ids);
      NotificationService.instance.markAllPresented(ids);
    }

    // 2. Resolve target notification IDs to mark as read in Firestore
    List<String> unreadIds = [];
    if (currentNotifs != null && currentNotifs.isNotEmpty) {
      unreadIds = currentNotifs
          .where((n) => !n.readByUserIds.contains(uid))
          .map((n) => n.id)
          .toList();
    } else {
      try {
        final querySnap = await firestore
            .collection(FirestoreCollections.households)
            .doc(householdId)
            .collection('notifications')
            .limit(40)
            .get();
        unreadIds = querySnap.docs
            .where((doc) {
              final readList =
                  (doc.data()['readByUserIds'] as List<dynamic>?) ?? [];
              return !readList.contains(uid);
            })
            .map((doc) => doc.id)
            .toList();

        // Also add any newly discovered IDs to local read set
        ref.read(locallyReadNotificationIdsProvider.notifier).markIds(unreadIds);
      } catch (e) {
        // Fallback silently
      }
    }

    if (unreadIds.isEmpty) return;

    // 3. Persist to Firestore
    try {
      final batch = firestore.batch();
      for (final docId in unreadIds) {
        final doc = firestore
            .collection(FirestoreCollections.households)
            .doc(householdId)
            .collection('notifications')
            .doc(docId);
        batch.update(doc, {
          'readByUserIds': FieldValue.arrayUnion([uid]),
        });
      }
      await batch.commit();
    } catch (e) {
      // Non-fatal if offline or network delay; local badge already cleared
    }
  }

  /// Mark an individual notification as read.
  Future<void> markAsRead(String notificationId) async {
    final householdId = ref.read(currentHouseholdProvider).value?.id ??
        ref.read(sessionProvider).value?.householdId;
    final authUid = FirebaseAuth.instance.currentUser?.uid;
    final uid = (authUid != null && authUid.isNotEmpty)
        ? authUid
        : (ref.read(sessionProvider).value?.user?.id ??
            ref.read(currentUserProvider).value?.id);
    if (householdId == null || uid == null) return;

    // Immediate local clearance
    ref.read(locallyReadNotificationIdsProvider.notifier).markOne(notificationId);
    NotificationService.instance.markPresented(notificationId);

    try {
      await FirebaseFirestore.instance
          .collection(FirestoreCollections.households)
          .doc(householdId)
          .collection('notifications')
          .doc(notificationId)
          .update({
        'readByUserIds': FieldValue.arrayUnion([uid]),
      });
    } catch (_) {}
  }
}

final notificationActionsProvider =
    AsyncNotifierProvider<NotificationActions, void>(NotificationActions.new);

/// Count of notifications the current user has not marked read.
/// Evaluates both Firestore status and instant local views.
final unreadNotificationCountProvider = Provider<int>((ref) {
  final authUid = FirebaseAuth.instance.currentUser?.uid;
  final sessionUid = ref.watch(sessionProvider).value?.user?.id;
  final currentUid = ref.watch(currentUserProvider).value?.id;
  final uid = (authUid != null && authUid.isNotEmpty)
      ? authUid
      : (sessionUid != null && sessionUid.isNotEmpty)
          ? sessionUid
          : currentUid;
  if (uid == null || uid.isEmpty) return 0;

  final notifications =
      ref.watch(householdNotificationsProvider).value ?? const [];
  final locallyRead = ref.watch(locallyReadNotificationIdsProvider);

  return notifications.where((notification) {
    if (notification.isCreatedBy(uid)) return false;
    if (locallyRead.contains(notification.id)) return false;
    return !notification.readByUserIds.contains(uid);
  }).length;
});
