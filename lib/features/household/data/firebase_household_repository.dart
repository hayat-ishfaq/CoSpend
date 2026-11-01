import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/firestore_constants.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/errors/firebase_error_mapper.dart';
import '../../../core/utils/validators.dart';
import '../../../core/services/notification_service.dart';
import '../../../shared/models/household.dart';
import '../../../shared/models/household_member.dart';
import '../../expenses/domain/custom_category.dart';
import '../domain/household_repository.dart';
import '../domain/invite_code.dart';

/// Firestore implementation of [HouseholdRepository].
class FirebaseHouseholdRepository implements HouseholdRepository {
  FirebaseHouseholdRepository(this._auth, this._firestore);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  static final RegExp _invitePattern = RegExp(r'^FLAT-[A-Z0-9]{4}$');

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthException('Your session ended. Please sign in again.');
    }
    return user.uid;
  }

  Future<Map<String, dynamic>> _currentUserProfile() async {
    final snapshot = await _firestore
        .collection(FirestoreCollections.users)
        .doc(_uid)
        .get();
    return snapshot.data() ?? const {};
  }

  Future<String> _uniqueInviteCode() async {
    for (var attempt = 0; attempt < 6; attempt++) {
      final code = InviteCode.generate(Random.secure());
      final existing = await _firestore
          .doc('${FirestoreCollections.inviteCodes}/$code')
          .get();
      if (!existing.exists) return code;
    }
    throw const HouseholdException(
      "Couldn't find a free invite code. Please try again.",
    );
  }

  @override
  Future<Household> createHousehold({required String name}) async {
    try {
      final uid = _uid;
      final profile = await _currentUserProfile();
      final code = await _uniqueInviteCode();
      final householdRef =
          _firestore.collection(FirestoreCollections.households).doc();
      final now = DateTime.now();

      final household = Household(
        id: householdRef.id,
        name: name.trim(),
        ownerId: uid,
        inviteCode: code,
        memberCount: 1,
        monthlyBudgetPaisa: 0,
        currency: AppConstants.defaultCurrency,
        createdAt: now,
      );

      final member = HouseholdMember(
        id: uid,
        name: profile['name'] as String? ?? 'FlatOwner',
        email: profile['email'] as String? ?? '',
        photoUrl: profile['photoUrl'] as String?,
        role: MemberRole.owner,
        joinedAt: now,
      );

      final batch = _firestore.batch();
      batch.set(householdRef, household.toMap());
      batch.set(
        _firestore
            .doc('${FirestoreCollections.inviteCodes}/$code'),
        {
          'householdId': household.id,
          'createdAt': Timestamp.fromDate(now),
        },
      );
      batch.set(
        householdRef
            .collection(FirestoreCollections.members)
            .doc(uid),
        member.toMap(),
      );
      batch.set(
        _firestore.collection(FirestoreCollections.users).doc(uid),
        {'householdId': household.id},
        SetOptions(merge: true),
      );
      await batch.commit();
      return household;
    } catch (error) {
      throw toAppException(error);
    }
  }

  @override
  Future<Household> joinHousehold({required String inviteCode}) async {
    try {
      final uid = _uid;
      final rawTrimmed = inviteCode.trim();
      final code = Validators.normalizeInviteCode(rawTrimmed);
      if (!_invitePattern.hasMatch(code)) {
        throw const HouseholdException(
          'That invite code looks wrong — codes look like FLAT-7K29.',
        );
      }

      String? householdId;

      // Strategy 1: Check inviteCodes collection with normalized code (e.g. FLAT-7K29)
      final codeSnapshot = await _firestore
          .doc('${FirestoreCollections.inviteCodes}/$code')
          .get();
      if (codeSnapshot.exists) {
        householdId = codeSnapshot.data()?['householdId'] as String?;
      }

      // Strategy 2: Check raw trimmed input (e.g. flat-7k29 or uppercase)
      if (householdId == null || householdId.isEmpty) {
        final rawUpper = rawTrimmed.toUpperCase();
        if (rawUpper != code) {
          final rawSnapshot = await _firestore
              .doc('${FirestoreCollections.inviteCodes}/$rawUpper')
              .get();
          if (rawSnapshot.exists) {
            householdId = rawSnapshot.data()?['householdId'] as String?;
          }
        }
      }

      // Strategy 3: Check short 4-character suffix in inviteCodes (e.g. 7K29)
      if (householdId == null || householdId.isEmpty) {
        final suffix = code.startsWith(AppConstants.invitePrefix)
            ? code.substring(AppConstants.invitePrefix.length)
            : code;
        final suffixSnapshot = await _firestore
            .doc('${FirestoreCollections.inviteCodes}/$suffix')
            .get();
        if (suffixSnapshot.exists) {
          householdId = suffixSnapshot.data()?['householdId'] as String?;
        }
      }

      // Strategy 4: Query households collection directly where inviteCode == normalized code
      if (householdId == null || householdId.isEmpty) {
        try {
          final query = await _firestore
              .collection(FirestoreCollections.households)
              .where('inviteCode', isEqualTo: code)
              .limit(1)
              .get();
          if (query.docs.isNotEmpty) {
            householdId = query.docs.first.id;
          }
        } catch (_) {}
      }

      // Strategy 5: Query households where inviteCode == suffix (without prefix)
      if (householdId == null || householdId.isEmpty) {
        final suffix = code.startsWith(AppConstants.invitePrefix)
            ? code.substring(AppConstants.invitePrefix.length)
            : code;
        try {
          final query = await _firestore
              .collection(FirestoreCollections.households)
              .where('inviteCode', isEqualTo: suffix)
              .limit(1)
              .get();
          if (query.docs.isNotEmpty) {
            householdId = query.docs.first.id;
          }
        } catch (_) {}
      }

      if (householdId == null || householdId.isEmpty) {
        throw const HouseholdException(
          "That invite code doesn't match any flat. "
          'Double-check it with whoever shared it.',
        );
      }

      // Auto-heal inviteCodes doc if resolved via fallback
      if (!codeSnapshot.exists) {
        _firestore
            .doc('${FirestoreCollections.inviteCodes}/$code')
            .set({
              'householdId': householdId,
              'createdAt': Timestamp.now(),
            }, SetOptions(merge: true))
            .catchError((_) {});
      }

      final householdRef = _firestore
          .collection(FirestoreCollections.households)
          .doc(householdId);

      final profile = await _currentUserProfile();
      final now = DateTime.now();

      // Check if user is already a member of this household
      final memberDocRef = householdRef
          .collection(FirestoreCollections.members)
          .doc(uid);
      final memberSnapshot = await memberDocRef.get();
      final alreadyMember = memberSnapshot.exists;

      final member = HouseholdMember(
        id: uid,
        name: profile['name'] as String? ??
            _auth.currentUser?.displayName ??
            'Flatmate',
        email: profile['email'] as String? ??
            _auth.currentUser?.email ??
            '',
        photoUrl: profile['photoUrl'] as String? ??
            _auth.currentUser?.photoURL,
        role: alreadyMember
            ? HouseholdMember.fromMap(uid, memberSnapshot.data()!).role
            : MemberRole.member,
        joinedAt: alreadyMember
            ? (memberSnapshot.data()?['joinedAt'] as Timestamp?)?.toDate() ??
                now
            : now,
      );

      // Core Join Write: add member and associate user with household
      final joinBatch = _firestore.batch();
      joinBatch.set(memberDocRef, member.toMap());
      joinBatch.set(
        _firestore.collection(FirestoreCollections.users).doc(uid),
        {'householdId': householdId},
        SetOptions(merge: true),
      );
      await joinBatch.commit();

      // Secondary non-fatal updates: memberCount increment, notification, and old flat cleanup
      if (!alreadyMember) {
        householdRef.update({
          'memberCount': FieldValue.increment(1),
        }).catchError((e) {
          debugPrint('Non-fatal memberCount increment error: $e');
        });

        final notifRef = householdRef.collection('notifications').doc();
        NotificationService.instance.markPresented(notifRef.id);
        notifRef.set({
          'householdId': householdId,
          'title': 'New roommate joined! 🎉',
          'body': '${member.name} joined the flat',
          'amountPaisa': 0,
          'category': 'Household',
          'subcategory': null,
          'payerName': member.name,
          'payerId': uid,
          'creatorId': uid,
          'createdAt': FieldValue.serverTimestamp(),
          'readByUserIds': <String>[uid],
        }).catchError((e) {
          debugPrint('Non-fatal notification write error: $e');
        });
      }

      final oldHouseholdId = profile['householdId'] as String?;
      if (oldHouseholdId != null &&
          oldHouseholdId.isNotEmpty &&
          oldHouseholdId != householdId) {
        () async {
          try {
            final oldRef = _firestore
                .collection(FirestoreCollections.households)
                .doc(oldHouseholdId);
            await oldRef.collection(FirestoreCollections.members).doc(uid).delete();
            await oldRef.update({'memberCount': FieldValue.increment(-1)});
          } catch (e) {
            debugPrint('Non-fatal cleanup of old flat $oldHouseholdId: $e');
          }
        }();
      }

      final joinedSnapshot = await householdRef.get();
      if (!joinedSnapshot.exists) {
        return Household(
          id: householdId,
          name: 'Flat',
          ownerId: uid,
          inviteCode: code,
          memberCount: 1,
          monthlyBudgetPaisa: 0,
          currency: AppConstants.defaultCurrency,
          createdAt: now,
        );
      }
      return Household.fromMap(householdId, joinedSnapshot.data()!);
    } catch (error) {
      throw toAppException(error);
    }
  }

  @override
  Stream<Household?> watchHousehold(String householdId) => _firestore
      .doc('${FirestoreCollections.households}/$householdId')
      .snapshots()
      .map((snapshot) => snapshot.exists
          ? Household.fromMap(snapshot.id, snapshot.data()!)
          : null);

  @override
  Stream<List<HouseholdMember>> watchMembers(String householdId) => _firestore
      .collection(
        '${FirestoreCollections.households}/'
        '$householdId/${FirestoreCollections.members}',
      )
      .orderBy('joinedAt')
      .snapshots()
      .map((snapshot) => snapshot.docs
          .map((doc) => HouseholdMember.fromMap(doc.id, doc.data()))
          .toList());

  @override
  Future<void> leaveHousehold() async {
    try {
      final uid = _uid;
      final userSnapshot = await _firestore
          .collection(FirestoreCollections.users)
          .doc(uid)
          .get();
      final householdId = userSnapshot.data()?['householdId'] as String?;
      if (householdId == null) return;

      final batch = _firestore.batch();
      batch.delete(_firestore
          .collection(FirestoreCollections.households)
          .doc(householdId)
          .collection(FirestoreCollections.members)
          .doc(uid));
      batch.update(
        _firestore
            .collection(FirestoreCollections.households)
            .doc(householdId),
        {'memberCount': FieldValue.increment(-1)},
      );
      batch.set(
        _firestore.collection(FirestoreCollections.users).doc(uid),
        {'householdId': FieldValue.delete()},
        SetOptions(merge: true),
      );
      await batch.commit();
    } catch (error) {
      throw toAppException(error);
    }
  }

  Future<void> _assertOwner(String householdId) async {
    final uid = _uid;
    final doc = await _firestore
        .collection(FirestoreCollections.households)
        .doc(householdId)
        .get();
    if (!doc.exists) throw const NotFoundException();
    final ownerId = doc.data()?['ownerId'] as String?;
    if (ownerId != null && ownerId.isNotEmpty && ownerId != uid) {
      throw const HouseholdException(
        'Only the flat owner can adjust budgets or household settings.',
      );
    }
  }

  @override
  Future<void> updateMonthlyBudget({
    required String householdId,
    required int budgetPaisa,
  }) async {
    try {
      await _assertOwner(householdId);
      await _firestore
          .collection(FirestoreCollections.households)
          .doc(householdId)
          .update({'monthlyBudgetPaisa': budgetPaisa});
    } catch (error) {
      throw toAppException(error);
    }
  }

  @override
  Future<void> renameHousehold({
    required String householdId,
    required String name,
  }) async {
    try {
      await _assertOwner(householdId);
      await _firestore
          .collection(FirestoreCollections.households)
          .doc(householdId)
          .update({'name': name.trim()});
    } catch (error) {
      throw toAppException(error);
    }
  }

  @override
  Future<void> updateCategoryBudgets({
    required String householdId,
    required Map<String, int> categoryBudgetsPaisa,
    Map<String, Map<String, int>> memberCategoryBudgetsPaisa = const {},
  }) async {
    try {
      await _assertOwner(householdId);
      final totalPaisa =
          categoryBudgetsPaisa.values.fold<int>(0, (a, b) => a + b);
      await _firestore
          .collection(FirestoreCollections.households)
          .doc(householdId)
          .update({
        'categoryBudgetsPaisa': categoryBudgetsPaisa,
        'memberCategoryBudgetsPaisa': memberCategoryBudgetsPaisa,
        'monthlyBudgetPaisa': totalPaisa,
      });
    } catch (error) {
      throw toAppException(error);
    }
  }

  @override
  Future<void> addCustomCategory({
    required String householdId,
    required CustomCategory category,
  }) async {
    try {
      await _assertOwner(householdId);
      await _firestore
          .collection(FirestoreCollections.households)
          .doc(householdId)
          .update({
        'customCategories': FieldValue.arrayUnion([category.toMap()]),
      });
    } catch (error) {
      throw toAppException(error);
    }
  }

  @override
  Future<void> addSubcategory({
    required String householdId,
    required String categoryId,
    required String subcategory,
  }) async {
    try {
      await _firestore
          .collection(FirestoreCollections.households)
          .doc(householdId)
          .update({
        'categorySubcategories.$categoryId':
            FieldValue.arrayUnion([subcategory.trim()]),
      });
    } catch (error) {
      throw toAppException(error);
    }
  }
}