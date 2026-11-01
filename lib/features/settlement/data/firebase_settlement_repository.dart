import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_constants.dart';
import '../../../core/errors/firebase_error_mapper.dart';
import '../../../core/services/notification_service.dart';
import '../domain/settlement.dart';
import '../domain/settlement_repository.dart';

class FirebaseSettlementRepository implements SettlementRepository {
  FirebaseSettlementRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _collection(String householdId) =>
      _firestore.collection(
        '${FirestoreCollections.households}/$householdId/${FirestoreCollections.settlements}',
      );

  RecordedSettlement _fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    DateTime settledAt = DateTime.now();
    final raw = data['settledAt'];
    if (raw is Timestamp) {
      settledAt = raw.toDate();
    }
    return RecordedSettlement(
      id: doc.id,
      fromUserId: data['fromUserId'] as String? ?? '',
      toUserId: data['toUserId'] as String? ?? '',
      amountPaisa: (data['amountPaisa'] as num?)?.toInt() ?? 0,
      recordedByUserId: data['recordedByUserId'] as String? ?? '',
      settledAt: settledAt,
    );
  }

  @override
  Stream<List<RecordedSettlement>> watchSettlements(String householdId) {
    return _collection(householdId)
        .orderBy('settledAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_fromDoc).toList());
  }

  @override
  Future<void> recordSettlement({
    required String householdId,
    required SettlementTransfer transfer,
    required String recordedByUserId,
  }) async {
    try {
      final batch = _firestore.batch();
      final settlementRef = _collection(householdId).doc();
      batch.set(settlementRef, {
        'fromUserId': transfer.fromMemberId,
        'toUserId': transfer.toMemberId,
        'amountPaisa': transfer.amountPaisa,
        'recordedByUserId': recordedByUserId,
        'settledAt': FieldValue.serverTimestamp(),
      });

      // Look up member names for the broadcast notification
      String fromName = 'A roommate';
      String toName = 'a roommate';
      try {
        final fromDoc = await _firestore
            .collection(FirestoreCollections.users)
            .doc(transfer.fromMemberId)
            .get();
        final toDoc = await _firestore
            .collection(FirestoreCollections.users)
            .doc(transfer.toMemberId)
            .get();
        fromName = fromDoc.data()?['name'] as String? ?? 'A roommate';
        toName = toDoc.data()?['name'] as String? ?? 'a roommate';
      } catch (_) {}

      final amountRupees = (transfer.amountPaisa / 100).toStringAsFixed(0);
      final notifRef = _firestore
          .collection(FirestoreCollections.households)
          .doc(householdId)
          .collection('notifications')
          .doc();

      // Ensure the recorder does not trigger self-notification or unread counter locally
      NotificationService.instance.markPresented(notifRef.id);

      batch.set(notifRef, {
        'householdId': householdId,
        'title': 'Payment settled: Rs. $amountRupees',
        'body': '$fromName paid $toName Rs. $amountRupees',
        'amountPaisa': transfer.amountPaisa,
        'category': 'Settlement',
        'subcategory': null,
        'payerName': fromName,
        'payerId': recordedByUserId,
        'creatorId': recordedByUserId,
        'createdAt': FieldValue.serverTimestamp(),
        'readByUserIds': <String>{
          if (recordedByUserId.isNotEmpty) recordedByUserId,
          if (transfer.fromMemberId.isNotEmpty) transfer.fromMemberId,
        }.toList(),
      });

      await batch.commit();
    } catch (error) {
      throw toAppException(error);
    }
  }
}
