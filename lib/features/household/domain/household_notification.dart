import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents an activity/spending notification broadcasted to household members.
class HouseholdNotification {
  const HouseholdNotification({
    required this.id,
    required this.householdId,
    required this.title,
    required this.body,
    required this.amountPaisa,
    required this.category,
    this.subcategory,
    required this.payerName,
    required this.payerId,
    this.creatorId,
    required this.createdAt,
    this.readByUserIds = const [],
  });

  final String id;
  final String householdId;
  final String title;
  final String body;
  final int amountPaisa;
  final String category;
  final String? subcategory;
  final String payerName;
  final String payerId;
  final String? creatorId;
  final DateTime createdAt;
  final List<String> readByUserIds;

  /// Returns true if this notification was initiated by [userId].
  bool isCreatedBy(String userId) {
    if (userId.isEmpty) return false;
    return payerId == userId || (creatorId != null && creatorId == userId);
  }

  factory HouseholdNotification.fromMap(String id, Map<String, dynamic> map) {
    DateTime parsedDate = DateTime.now();
    final rawDate = map['createdAt'];
    if (rawDate is Timestamp) {
      parsedDate = rawDate.toDate();
    } else if (rawDate is String) {
      parsedDate = DateTime.tryParse(rawDate) ?? DateTime.now();
    }

    return HouseholdNotification(
      id: id,
      householdId: map['householdId'] as String? ?? '',
      title: map['title'] as String? ?? 'Expense added',
      body: map['body'] as String? ?? '',
      amountPaisa: (map['amountPaisa'] as num?)?.toInt() ?? 0,
      category: map['category'] as String? ?? 'General',
      subcategory: map['subcategory'] as String?,
      payerName: map['payerName'] as String? ?? 'Flatmate',
      payerId: map['payerId'] as String? ?? '',
      creatorId: map['creatorId'] as String? ?? map['createdByUserId'] as String?,
      createdAt: parsedDate,
      readByUserIds: (map['readByUserIds'] as List<dynamic>?)
              ?.map((id) => id.toString())
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'householdId': householdId,
      'title': title,
      'body': body,
      'amountPaisa': amountPaisa,
      'category': category,
      'subcategory': subcategory,
      'payerName': payerName,
      'payerId': payerId,
      'creatorId': creatorId,
      'createdAt': Timestamp.fromDate(createdAt),
      'readByUserIds': readByUserIds,
    };
  }
}
