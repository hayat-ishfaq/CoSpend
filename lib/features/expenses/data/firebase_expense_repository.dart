import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_constants.dart';
import '../../../core/errors/firebase_error_mapper.dart';
import '../../../core/services/notification_service.dart';
import '../domain/expense.dart';
import '../domain/expense_repository.dart';

class FirebaseExpenseRepository implements ExpenseRepository {
  FirebaseExpenseRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _collection(String householdId) =>
      _firestore.collection(
        '${FirestoreCollections.households}/$householdId/${FirestoreCollections.expenses}',
      );

  @override
  Future<Expense> createExpense(Expense expense) async {
    try {
      final docRef = _collection(expense.householdId).doc();
      final newExpense = Expense(
        id: docRef.id,
        householdId: expense.householdId,
        description: expense.description,
        category: expense.category,
        customCategoryId: expense.customCategoryId,
        subcategory: expense.subcategory,
        amountPaisa: expense.amountPaisa,
        paidById: expense.paidById,
        splitAmongIds: expense.splitAmongIds,
        splitAmountsPaisa: expense.splitAmountsPaisa,
        spentAt: expense.spentAt,
        createdByUserId: expense.createdByUserId,
        createdAt: expense.createdAt,
        splitType: expense.splitType,
      );

      final batch = _firestore.batch();
      batch.set(docRef, newExpense.toMap());

      // Broadcast notification document for flatmates
      final notifRef = _firestore
          .collection(FirestoreCollections.households)
          .doc(expense.householdId)
          .collection('notifications')
          .doc();

      // Ensure the creator does not trigger a self-notification or unread counter locally
      NotificationService.instance.markPresented(notifRef.id);

      final userDoc = await _firestore
          .collection(FirestoreCollections.users)
          .doc(expense.paidById)
          .get();
      final payerName = userDoc.data()?['name'] as String? ?? 'A roommate';

      final categoryLabel = expense.customCategoryId != null
          ? 'Custom'
          : expense.category.label;

      final amountRupees = (expense.amountPaisa / 100).toStringAsFixed(0);
      final subcatText = expense.subcategory != null && expense.subcategory!.isNotEmpty
          ? ' (${expense.subcategory})'
          : '';

      batch.set(notifRef, {
        'householdId': expense.householdId,
        'title': '$payerName spent Rs. $amountRupees',
        'body': 'Rs. $amountRupees on $categoryLabel$subcatText',
        'amountPaisa': expense.amountPaisa,
        'category': categoryLabel,
        'subcategory': expense.subcategory,
        'payerName': payerName,
        'payerId': expense.paidById,
        'creatorId': expense.createdByUserId,
        'createdAt': FieldValue.serverTimestamp(),
        'readByUserIds': <String>{
          if (expense.paidById.isNotEmpty) expense.paidById,
          if (expense.createdByUserId.isNotEmpty) expense.createdByUserId,
        }.toList(),
      });

      await batch.commit();
      return newExpense;
    } catch (error) {
      throw toAppException(error);
    }
  }

  @override
  Future<void> updateExpense(Expense expense) async {
    try {
      await _collection(expense.householdId).doc(expense.id).set(
            expense.toMap(),
            SetOptions(merge: true),
          );
    } catch (error) {
      throw toAppException(error);
    }
  }

  @override
  Future<void> deleteExpense({
    required String householdId,
    required String expenseId,
  }) async {
    try {
      await _collection(householdId).doc(expenseId).delete();
    } catch (error) {
      throw toAppException(error);
    }
  }

  @override
  Stream<List<Expense>> watchExpenses(String householdId) {
    return _collection(householdId)
        .orderBy('spentAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Expense.fromMap(doc.id, doc.data()))
            .toList());
  }

  @override
  Stream<List<Expense>> watchRecentExpenses(
    String householdId, {
    int limit = 5,
  }) {
    return _collection(householdId)
        .orderBy('spentAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Expense.fromMap(doc.id, doc.data()))
            .toList());
  }
}
