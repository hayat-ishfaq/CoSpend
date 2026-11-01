import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/errors/firebase_error_mapper.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/money.dart';
import '../../../../shared/models/household.dart';
import '../../../../shared/models/household_member.dart';
import '../../../../shared/widgets/app_avatar.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../auth/presentation/providers/session_provider.dart';
import '../../../expenses/domain/expense_category.dart';
import '../../../expenses/presentation/widgets/create_category_sheet.dart';
import '../../../household/presentation/providers/household_providers.dart';
import '../../../household/presentation/widgets/notification_bell_button.dart';
import '../../domain/dashboard_stats.dart';
import '../providers/dashboard_providers.dart';
import '../widgets/budget_alert_card.dart';
import '../widgets/budget_category_item.dart';
import '../widgets/budget_guide_sheet.dart';
import '../widgets/category_detail_sheet.dart';
import '../widgets/manage_limits_sheet.dart';
import '../widgets/spending_trends_sheet.dart';

typedef _BudgetCategoryItem = BudgetCategoryItem;

class CategoryBudgetScreen extends ConsumerStatefulWidget {
  const CategoryBudgetScreen({super.key});

  @override
  ConsumerState<CategoryBudgetScreen> createState() =>
      _CategoryBudgetScreenState();
}

class _CategoryBudgetScreenState extends ConsumerState<CategoryBudgetScreen> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, Map<String, TextEditingController>> _memberControllers = {};
  final Set<String> _expandedCategories = {};
  bool _initialized = false;

  List<_BudgetCategoryItem> _getCategoryItems(Household? household) {
    final list = <_BudgetCategoryItem>[];
    if (household != null && household.customCategories.isNotEmpty) {
      for (final custom in household.customCategories) {
        list.add(_BudgetCategoryItem(
          id: custom.id,
          label: custom.label,
          icon: custom.icon,
          color: custom.color,
          isCustom: true,
        ));
      }
    }
    for (final cat in ExpenseCategory.values) {
      list.add(_BudgetCategoryItem(
        id: cat.id,
        label: cat.label,
        icon: cat.icon,
        color: cat.color,
        isCustom: false,
      ));
    }
    return list;
  }

  @override
  void initState() {
    super.initState();
    for (final cat in ExpenseCategory.values) {
      _controllers[cat.id] = TextEditingController();
      _memberControllers[cat.id] = {};
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final m in _memberControllers.values) {
      for (final c in m.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  void _populateFromHousehold() {
    if (_initialized) return;
    final household = ref.read(currentHouseholdProvider).value;
    final members = ref.read(householdMembersProvider).value ?? const [];
    if (household == null) return;

    final items = _getCategoryItems(household);
    for (final item in items) {
      final paisa = household.categoryBudgetsPaisa[item.id] ?? 0;
      _controllers[item.id] ??= TextEditingController();
      if (paisa > 0) {
        final rupees = (paisa / 100).round();
        _controllers[item.id]!.text = rupees.toString();
      }

      _memberControllers[item.id] ??= {};
      for (final member in members) {
        final memberPaisa =
            household.getMemberCategoryBudget(item.id, member.id);
        var ctrl = _memberControllers[item.id]?[member.id];
        if (ctrl == null) {
          ctrl = TextEditingController(
            text:
                memberPaisa > 0 ? (memberPaisa / 100).round().toString() : '',
          );
          _memberControllers[item.id]![member.id] = ctrl;
        } else if (memberPaisa > 0) {
          ctrl.text = (memberPaisa / 100).round().toString();
        }
      }
    }
    _initialized = true;
  }

  int _calculateTotalBudgetPaisa() {
    int total = 0;
    for (final c in _controllers.values) {
      final val = int.tryParse(c.text.trim()) ?? 0;
      total += val * 100;
    }
    return total;
  }

  void _splitEqually(String catId, List<HouseholdMember> members) {
    final catRupees = int.tryParse(_controllers[catId]?.text.trim() ?? '') ?? 0;
    if (catRupees <= 0 || members.isEmpty) return;

    final sharePerMember = (catRupees / members.length).round();
    for (final member in members) {
      var ctrl = _memberControllers[catId]?[member.id];
      if (ctrl == null) {
        ctrl = TextEditingController();
        _memberControllers[catId]![member.id] = ctrl;
      }
      ctrl.text = sharePerMember.toString();
    }
    _expandedCategories.add(catId);
    setState(() {});
  }

  Future<void> _saveBudgets() async {
    final household = ref.read(currentHouseholdProvider).value;
    if (household == null) return;

    final session = ref.read(sessionProvider).value;
    final currentUserId = session?.user?.id ?? '';
    final isOwner =
        household.ownerId.isEmpty || household.ownerId == currentUserId;
    if (!isOwner) {
      showAppSnack(
        context,
        'Only the flat owner can adjust budgets.',
        error: true,
      );
      return;
    }

    final Map<String, int> categoryBudgetsPaisa = {};
    final Map<String, Map<String, int>> memberCategoryBudgetsPaisa = {};

    for (final entry in _controllers.entries) {
      final rupees = int.tryParse(entry.value.text.trim()) ?? 0;
      if (rupees > 0) {
        categoryBudgetsPaisa[entry.key] = rupees * 100;

        final memberMap = _memberControllers[entry.key];
        if (memberMap != null) {
          final userBudgets = <String, int>{};
          for (final mEntry in memberMap.entries) {
            final mRupees = int.tryParse(mEntry.value.text.trim()) ?? 0;
            if (mRupees > 0) {
              userBudgets[mEntry.key] = mRupees * 100;
            }
          }
          if (userBudgets.isNotEmpty) {
            memberCategoryBudgetsPaisa[entry.key] = userBudgets;
          }
        }
      }
    }

    try {
      await ref.read(householdActionsProvider.notifier).updateCategoryBudgets(
            householdId: household.id,
            categoryBudgetsPaisa: categoryBudgetsPaisa,
            memberCategoryBudgetsPaisa: memberCategoryBudgetsPaisa,
          );

      if (!mounted) return;
      showAppSnack(context, 'Budgets updated successfully');
    } catch (e) {
      if (!mounted) return;
      showAppSnack(context, FirebaseErrorMapper.messageFor(e));
    }
  }

  void _addAmount(String catId, int deltaRupees) {
    final c = _controllers[catId];
    if (c == null) return;
    final current = int.tryParse(c.text.trim()) ?? 0;
    final updated = (current + deltaRupees).clamp(0, 10000000);
    c.text = updated > 0 ? updated.toString() : '';
    setState(() {});
  }

  void _bulkAdjustPercent(int percent, List<_BudgetCategoryItem> items) {
    HapticFeedback.mediumImpact();
    int count = 0;
    for (final item in items) {
      final ctrl = _controllers[item.id];
      if (ctrl != null) {
        final current = int.tryParse(ctrl.text.trim()) ?? 0;
        if (current > 0) {
          final updated = ((current * (100 + percent)) / 100).round();
          ctrl.text = updated > 0 ? updated.toString() : '';
          count++;
        }
      }
    }
    setState(() {});
    if (mounted) {
      showAppSnack(
        context,
        percent > 0
            ? 'Increased $count category limits by +$percent%'
            : 'Decreased $count category limits by $percent%',
      );
    }
  }

  void _autoDistributeBudget(int targetRupees, List<_BudgetCategoryItem> items) {
    if (items.isEmpty || targetRupees <= 0) return;
    HapticFeedback.mediumImpact();
    final perCat = (targetRupees / items.length).round();
    for (final item in items) {
      _controllers[item.id] ??= TextEditingController();
      _controllers[item.id]!.text = perCat.toString();
    }
    setState(() {});
    if (mounted) {
      showAppSnack(
        context,
        'Auto-distributed Rs. $targetRupees across ${items.length} categories',
      );
    }
  }

  void _splitAllEqually(
    List<_BudgetCategoryItem> items,
    List<HouseholdMember> members,
  ) {
    if (members.isEmpty) return;
    HapticFeedback.mediumImpact();
    int splitCount = 0;
    for (final item in items) {
      final catRupees = int.tryParse(_controllers[item.id]?.text.trim() ?? '') ?? 0;
      if (catRupees > 0) {
        final share = (catRupees / members.length).round();
        for (final m in members) {
          _memberControllers[item.id] ??= {};
          var mCtrl = _memberControllers[item.id]?[m.id];
          if (mCtrl == null) {
            mCtrl = TextEditingController(text: share.toString());
            _memberControllers[item.id]![m.id] = mCtrl;
          } else {
            mCtrl.text = share.toString();
          }
        }
        splitCount++;
      }
    }
    setState(() {});
    if (mounted) {
      showAppSnack(
        context,
        'Equally split $splitCount active category budgets among ${members.length} roommates',
      );
    }
  }

  void _clearAllBudgets(List<_BudgetCategoryItem> items) {
    HapticFeedback.heavyImpact();
    for (final item in items) {
      _controllers[item.id]?.clear();
      final m = _memberControllers[item.id];
      if (m != null) {
        for (final c in m.values) {
          c.clear();
        }
      }
    }
    setState(() {});
    if (mounted) {
      showAppSnack(context, 'Cleared all category budgets');
    }
  }

  void _matchCurrentSpending(
    List<_BudgetCategoryItem> items,
    DashboardStats stats,
  ) {
    HapticFeedback.mediumImpact();
    int updatedCount = 0;
    for (final item in items) {
      final spentPaisa = stats.categoryIdBreakdown[item.id] ?? 0;
      if (spentPaisa > 0) {
        final spentRupees = (spentPaisa / 100).ceil();
        // Round up to nearest 500 or 1000
        final rounded = spentRupees <= 1000
            ? ((spentRupees + 99) ~/ 100) * 100
            : ((spentRupees + 499) ~/ 500) * 500;
        _controllers[item.id] ??= TextEditingController();
        _controllers[item.id]!.text = rounded.toString();
        updatedCount++;
      }
    }
    setState(() {});
    if (mounted) {
      showAppSnack(
        context,
        'Matched $updatedCount category limits to actual spending',
      );
    }
  }

  void _toggleExpandAll(List<_BudgetCategoryItem> categoryItems) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_expandedCategories.length == categoryItems.length) {
        _expandedCategories.clear();
      } else {
        _expandedCategories.clear();
        _expandedCategories.addAll(categoryItems.map((e) => e.id));
      }
    });
  }

  void _openSpendingTrendsSheet({
    required BuildContext context,
    required DashboardStats stats,
    required List<_BudgetCategoryItem> categoryItems,
    required int totalBudgetPaisa,
    required int totalSpentPaisa,
    required bool isDark,
  }) {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SpendingTrendsSheet(
        stats: stats,
        categoryItems: categoryItems,
        totalBudgetPaisa: totalBudgetPaisa,
        totalSpentPaisa: totalSpentPaisa,
        isDark: isDark,
      ),
    );
  }

  void _openManageLimitsSheet({
    required BuildContext context,
    required bool isOwner,
    required bool isDark,
    required List<HouseholdMember> members,
    required List<_BudgetCategoryItem> categoryItems,
    required int totalBudgetPaisa,
  }) {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ManageLimitsSheet(
        isOwner: isOwner,
        isDark: isDark,
        members: members,
        categoryItems: categoryItems,
        totalBudgetPaisa: totalBudgetPaisa,
        onSave: () async {
          Navigator.pop(ctx);
          await _saveBudgets();
        },
        onBulkAdjustPercent: (percent) {
          Navigator.pop(ctx);
          _bulkAdjustPercent(percent, categoryItems);
        },
        onAutoDistribute: (targetRupees) {
          Navigator.pop(ctx);
          _autoDistributeBudget(targetRupees, categoryItems);
        },
        onSplitAllEqually: () {
          Navigator.pop(ctx);
          _splitAllEqually(categoryItems, members);
        },
        onClearAll: () {
          Navigator.pop(ctx);
          _clearAllBudgets(categoryItems);
        },
        onMatchCurrentSpending: () {
          Navigator.pop(ctx);
          _matchCurrentSpending(categoryItems, ref.read(dashboardStatsProvider));
        },
      ),
    );
  }

  void _openBudgetGuideSheet({
    required BuildContext context,
    required bool isDark,
  }) {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BudgetGuideSheet(isDark: isDark),
    );
  }

  void _openCategoryDetailSheet({
    required BuildContext context,
    required _BudgetCategoryItem catItem,
    required int budgetPaisa,
    required int spentPaisa,
    required List<HouseholdMember> members,
    required Map<String, TextEditingController> memberControllers,
    required bool isDark,
    required bool isOwner,
  }) {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CategoryDetailSheet(
        catItem: catItem,
        budgetPaisa: budgetPaisa,
        spentPaisa: spentPaisa,
        members: members,
        memberControllers: memberControllers,
        isDark: isDark,
        isOwner: isOwner,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final household = ref.watch(currentHouseholdProvider).value;
    final members = ref.watch(householdMembersProvider).value ?? const [];
    final session = ref.watch(sessionProvider).value;
    final currentUser = ref.watch(currentUserProvider).value ?? session?.user;
    final currentUserId = currentUser?.id ?? '';
    final isOwner = household != null &&
        (household.ownerId == currentUserId || household.ownerId.isEmpty);

    ref.listen(currentHouseholdProvider, (prev, next) {
      if (!_initialized && next.value != null) {
        setState(_populateFromHousehold);
      }
    });

    if (!_initialized) {
      _populateFromHousehold();
    }

    final categoryItems = _getCategoryItems(household);

    for (final catItem in categoryItems) {
      _controllers[catItem.id] ??= TextEditingController();
      _memberControllers[catItem.id] ??= {};
      for (final member in members) {
        if (!_memberControllers[catItem.id]!.containsKey(member.id)) {
          final memberPaisa =
              household?.getMemberCategoryBudget(catItem.id, member.id) ?? 0;
          _memberControllers[catItem.id]![member.id] = TextEditingController(
            text:
                memberPaisa > 0 ? (memberPaisa / 100).round().toString() : '',
          );
        }
      }
    }

    final stats = ref.watch(dashboardStatsProvider);
    final isSaving = ref.watch(householdActionsProvider).isLoading;
    final totalBudgetPaisa = _calculateTotalBudgetPaisa();
    final totalSpentPaisa = stats.totalSpendingPaisa;
    final remainingPaisa = totalBudgetPaisa - totalSpentPaisa;
    final pct = totalBudgetPaisa > 0
        ? ((totalSpentPaisa / totalBudgetPaisa) * 100).clamp(0.0, 100.0)
        : 0.0;
    final isOverall = totalBudgetPaisa > 0 && totalSpentPaisa > totalBudgetPaisa;
    final isApproachingOverall =
        totalBudgetPaisa > 0 && pct >= 80.0 && !isOverall;

    final statusLabel = isOverall
        ? 'OVER BUDGET'
        : isApproachingOverall
            ? 'APPROACHING'
            : 'ON TRACK';
    final statusColor = isOverall
        ? CoSpendColors.alertRed
        : isApproachingOverall
            ? CoSpendColors.warningAmber
            : CoSpendColors.jadeGreen;

    // Find exceeded categories for budget alert
    final exceededCategories = categoryItems.where((item) {
      final budgetPaisa =
          (int.tryParse(_controllers[item.id]?.text.trim() ?? '') ?? 0) * 100;
      final spentPaisa = stats.categoryIdBreakdown[item.id] ?? 0;
      return budgetPaisa > 0 && spentPaisa > budgetPaisa;
    }).toList();

    return Scaffold(
      backgroundColor: isDark ? CoSpendColors.darkCanvas : CoSpendColors.canvas,
      appBar: AppBar(
        backgroundColor: isDark ? CoSpendColors.darkCanvas : CoSpendColors.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: Icon(
                  Icons.arrow_back_ios_rounded,
                  size: 18,
                  color: isDark ? Colors.white : CoSpendColors.prussianBlue,
                ),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        title: Text(
          'BUDGETS HUB',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.8,
            color: isDark ? Colors.white : CoSpendColors.prussianBlue,
          ),
        ),
        actions: [
          if (isOwner)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: FilledButton.icon(
                onPressed: isSaving ? null : _saveBudgets,
                icon: isSaving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_rounded, size: 16),
                label: Text(
                  isSaving ? 'Saving...' : 'Save',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: CoSpendColors.jadeGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),
          const NotificationBellButton(),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () => context.push(Routes.profile),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: CoSpendColors.jadeGreen,
                    width: 2,
                  ),
                ),
                child: AppAvatar(
                  name: currentUser?.name ?? 'User',
                  photoUrl: currentUser?.photoUrl,
                  size: 32,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
              children: [
                // ── Summary Card ───────────────────────────────────────────
                _SummaryCard(
                  totalBudgetPaisa: totalBudgetPaisa,
                  totalSpentPaisa: totalSpentPaisa,
                  remainingPaisa: remainingPaisa,
                  pct: pct,
                  statusLabel: statusLabel,
                  statusColor: statusColor,
                  isDark: isDark,
                  onTap: () => _openSpendingTrendsSheet(
                    context: context,
                    stats: stats,
                    categoryItems: categoryItems,
                    totalBudgetPaisa: totalBudgetPaisa,
                    totalSpentPaisa: totalSpentPaisa,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(height: 14),

                // ── Action Buttons Row ─────────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.trending_up_rounded,
                        label: 'Spending Trends',
                        isDark: isDark,
                        onTap: () => _openSpendingTrendsSheet(
                          context: context,
                          stats: stats,
                          categoryItems: categoryItems,
                          totalBudgetPaisa: totalBudgetPaisa,
                          totalSpentPaisa: totalSpentPaisa,
                          isDark: isDark,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.tune_rounded,
                        label: 'Manage Limits',
                        isDark: isDark,
                        isLoading: isSaving,
                        onTap: () => _openManageLimitsSheet(
                          context: context,
                          isOwner: isOwner,
                          isDark: isDark,
                          members: members,
                          categoryItems: categoryItems,
                          totalBudgetPaisa: totalBudgetPaisa,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _ActionButton(
                      icon: Icons.info_outline_rounded,
                      label: '',
                      isDark: isDark,
                      isIconOnly: true,
                      onTap: () => _openBudgetGuideSheet(
                        context: context,
                        isDark: isDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // ── Categories Header ──────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Categories',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: isDark ? Colors.white : CoSpendColors.prussianBlue,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _toggleExpandAll(categoryItems),
                      child: Row(
                        children: [
                          Text(
                            _expandedCategories.length == categoryItems.length
                                ? 'Collapse All'
                                : 'See All',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: CoSpendColors.jadeGreen,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            _expandedCategories.length == categoryItems.length
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.arrow_forward_rounded,
                            size: 15,
                            color: CoSpendColors.jadeGreen,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // ── Category Cards ─────────────────────────────────────────
                for (final catItem in categoryItems) ...[
                  _CategoryBudgetCard(
                    catItem: catItem,
                    controller: _controllers[catItem.id]!,
                    memberControllers: _memberControllers[catItem.id] ?? {},
                    members: members,
                    spentPaisa: stats.categoryIdBreakdown[catItem.id] ?? 0,
                    isOwner: isOwner,
                    isExpanded: _expandedCategories.contains(catItem.id),
                    isDark: isDark,
                    onTapCategory: () {
                      final catRupees =
                          int.tryParse(_controllers[catItem.id]?.text.trim() ?? '') ?? 0;
                      _openCategoryDetailSheet(
                        context: context,
                        catItem: catItem,
                        budgetPaisa: catRupees * 100,
                        spentPaisa: stats.categoryIdBreakdown[catItem.id] ?? 0,
                        members: members,
                        memberControllers: _memberControllers[catItem.id] ?? {},
                        isDark: isDark,
                        isOwner: isOwner,
                      );
                    },
                    onToggleExpand: () {
                      setState(() {
                        if (_expandedCategories.contains(catItem.id)) {
                          _expandedCategories.remove(catItem.id);
                        } else {
                          _expandedCategories.add(catItem.id);
                        }
                      });
                    },
                    onAmountChanged: () => setState(() {}),
                    onAddAmount: (delta) => _addAmount(catItem.id, delta),
                    onSplitEqually: () =>
                        _splitEqually(catItem.id, members),
                  ),
                  const SizedBox(height: 10),
                ],

                // ── Add New Category Button ────────────────────────────────
                if (isOwner) ...[
                  GestureDetector(
                    onTap: () async {
                      final created = await CreateCategorySheet.show(context);
                      if (created != null && mounted) {
                        setState(() => _initialized = false);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: isDark ? CoSpendColors.darkCard : CoSpendColors.white,
                        borderRadius: CoSpendRadii.cardRadius,
                        border: Border.all(
                          color: isDark
                              ? CoSpendColors.darkBorder
                              : CoSpendColors.borderLight,
                          width: 1,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.add_circle_outline_rounded,
                            size: 20,
                            color: isDark
                                ? CoSpendColors.darkTextMuted
                                : CoSpendColors.textMuted,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Add New Category',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? CoSpendColors.darkTextMuted
                                  : CoSpendColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // ── Budget Alert Card ──────────────────────────────────────
                if (exceededCategories.isNotEmpty) ...[
                  BudgetAlertCard(
                    exceededCategory: exceededCategories.first,
                    spentPaisa: stats.categoryIdBreakdown[exceededCategories.first.id] ?? 0,
                    budgetPaisa: (int.tryParse(
                                  _controllers[exceededCategories.first.id]
                                          ?.text
                                          .trim() ??
                                      '',
                                ) ??
                                0) *
                            100,
                    onResolve: () => _saveBudgets(),
                  ),
                  const SizedBox(height: 20),
                ],
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: isOwner
          ? SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                decoration: BoxDecoration(
                  color: isDark ? CoSpendColors.darkCard : CoSpendColors.white,
                  border: Border(
                    top: BorderSide(
                      color: isDark ? CoSpendColors.darkBorder : CoSpendColors.borderLight,
                      width: 0.8,
                    ),
                  ),
                  boxShadow: isDark ? null : CoSpendShadows.navBar,
                ),
                child: Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        final created = await CreateCategorySheet.show(context);
                        if (created != null && mounted) {
                          setState(() => _initialized = false);
                        }
                      },
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add Category'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: CoSpendColors.jadeGreen,
                        side: const BorderSide(color: CoSpendColors.jadeGreen),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: isSaving ? null : _saveBudgets,
                        icon: isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_circle_outline_rounded, size: 18),
                        label: Text(
                          isSaving ? 'Saving Budgets...' : 'Save Category Budgets',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: CoSpendColors.jadeGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Summary Card with Donut Chart
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.totalBudgetPaisa,
    required this.totalSpentPaisa,
    required this.remainingPaisa,
    required this.pct,
    required this.statusLabel,
    required this.statusColor,
    required this.isDark,
    this.onTap,
  });

  final int totalBudgetPaisa;
  final int totalSpentPaisa;
  final int remainingPaisa;
  final double pct;
  final String statusLabel;
  final Color statusColor;
  final bool isDark;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monthLabel =
        '${_monthName(now.month)} ${now.year} Budget Cycle';

    return Material(
      color: Colors.transparent,
      borderRadius: CoSpendRadii.cardLargeRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: CoSpendRadii.cardLargeRadius,
        splashColor: CoSpendColors.jadeGreen.withValues(alpha: 0.1),
        highlightColor: CoSpendColors.jadeGreen.withValues(alpha: 0.05),
        child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? CoSpendColors.darkCard : CoSpendColors.white,
        borderRadius: CoSpendRadii.cardLargeRadius,
        border: Border.all(
          color: isDark ? CoSpendColors.darkBorder : CoSpendColors.borderLight,
          width: 0.8,
        ),
        boxShadow: isDark ? null : CoSpendShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row + status badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total Household\nSpending',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        height: 1.25,
                        color: isDark ? Colors.white : CoSpendColors.prussianBlue,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      monthLabel,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? CoSpendColors.darkTextMuted
                            : CoSpendColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: CoSpendRadii.pillRadius,
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      statusLabel == 'ON TRACK'
                          ? Icons.check_circle_rounded
                          : Icons.warning_amber_rounded,
                      size: 12,
                      color: statusColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Donut chart
          Center(
            child: SizedBox(
              width: 160,
              height: 160,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(160, 160),
                    painter: _DonutPainter(
                      progress: pct / 100.0,
                      foregroundColor: statusColor,
                      backgroundColor: isDark
                          ? CoSpendColors.darkBorder
                          : const Color(0xFFEEF2F7),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${pct.toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1,
                          color: isDark ? Colors.white : CoSpendColors.prussianBlue,
                        ),
                      ),
                      Text(
                        'SPENT',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: isDark
                              ? CoSpendColors.darkTextMuted
                              : CoSpendColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Total spent / remaining row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'TOTAL SPENT',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: isDark
                                ? CoSpendColors.darkTextMuted
                                : CoSpendColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      Money.format(totalSpentPaisa),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: isDark ? Colors.white : CoSpendColors.prussianBlue,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 1,
                height: 36,
                color: isDark ? CoSpendColors.darkBorder : CoSpendColors.borderLight,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'REMAINING',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: isDark
                              ? CoSpendColors.darkTextMuted
                              : CoSpendColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        totalBudgetPaisa > 0
                            ? Money.format(remainingPaisa.abs())
                            : 'No budget set',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: remainingPaisa < 0
                              ? CoSpendColors.alertRed
                              : (isDark
                                  ? Colors.white
                                  : CoSpendColors.prussianBlue),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: CoSpendColors.jadeGreen.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Tap card for spending trends & analytics',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: CoSpendColors.jadeGreen,
                  ),
                ),
                SizedBox(width: 4),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 13,
                  color: CoSpendColors.jadeGreen,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  ),
);
  }
}

String _monthName(int month) {
  const names = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  return names[(month - 1).clamp(0, 11)];
}

// ─────────────────────────────────────────────────────────────────────────────
// Donut Chart Painter
// ─────────────────────────────────────────────────────────────────────────────

class _DonutPainter extends CustomPainter {
  const _DonutPainter({
    required this.progress,
    required this.foregroundColor,
    required this.backgroundColor,
  });

  final double progress;
  final Color foregroundColor;
  final Color backgroundColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 12;
    const strokeWidth = 18.0;

    final bgPaint = Paint()
      ..color = backgroundColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, bgPaint);

    final fgPaint = Paint()
      ..color = foregroundColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final sweepAngle = 2 * math.pi * progress.clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweepAngle,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.foregroundColor != foregroundColor;
}

// ─────────────────────────────────────────────────────────────────────────────
// Action Button
// ─────────────────────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.isDark,
    this.onTap,
    this.isLoading = false,
    this.isIconOnly = false,
  });

  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback? onTap;
  final bool isLoading;
  final bool isIconOnly;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isIconOnly ? 14 : 12,
          vertical: 11,
        ),
        decoration: BoxDecoration(
          color: isDark ? CoSpendColors.darkCard : CoSpendColors.white,
          borderRadius: CoSpendRadii.cardRadius,
          border: Border.all(
            color: isDark ? CoSpendColors.darkBorder : CoSpendColors.borderLight,
            width: 0.8,
          ),
          boxShadow: isDark ? null : CoSpendShadows.cardSubtle,
        ),
        child: isLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: CoSpendColors.jadeGreen,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: isDark
                        ? CoSpendColors.darkTextMuted
                        : CoSpendColors.textMuted,
                  ),
                  if (!isIconOnly && label.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? CoSpendColors.darkTextMuted
                              : CoSpendColors.textMuted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Category Budget Card
// ─────────────────────────────────────────────────────────────────────────────

class _CategoryBudgetCard extends StatelessWidget {
  const _CategoryBudgetCard({
    required this.catItem,
    required this.controller,
    required this.memberControllers,
    required this.members,
    required this.spentPaisa,
    required this.isOwner,
    required this.isExpanded,
    required this.isDark,
    required this.onToggleExpand,
    required this.onAmountChanged,
    required this.onAddAmount,
    required this.onSplitEqually,
    this.onTapCategory,
  });

  final _BudgetCategoryItem catItem;
  final TextEditingController controller;
  final Map<String, TextEditingController> memberControllers;
  final List<HouseholdMember> members;
  final int spentPaisa;
  final bool isOwner;
  final bool isExpanded;
  final bool isDark;
  final VoidCallback onToggleExpand;
  final VoidCallback onAmountChanged;
  final void Function(int delta) onAddAmount;
  final VoidCallback onSplitEqually;
  final VoidCallback? onTapCategory;

  @override
  Widget build(BuildContext context) {
    final catBudgetRupees = int.tryParse(controller.text.trim()) ?? 0;
    final catBudgetPaisa = catBudgetRupees * 100;
    final isOver = catBudgetPaisa > 0 && spentPaisa > catBudgetPaisa;
    final isApproaching =
        catBudgetPaisa > 0 && !isOver && spentPaisa >= catBudgetPaisa * 0.8;

    final pct = catBudgetPaisa > 0
        ? (spentPaisa / catBudgetPaisa * 100).clamp(0.0, 100.0)
        : 0.0;
    final progressColor = isOver
        ? CoSpendColors.alertRed
        : isApproaching
            ? CoSpendColors.warningAmber
            : CoSpendColors.jadeGreen;

    final remaining = catBudgetPaisa - spentPaisa;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? CoSpendColors.darkCard : CoSpendColors.white,
        borderRadius: CoSpendRadii.cardRadius,
        border: Border.all(
          color: isOver
              ? CoSpendColors.alertRed.withValues(alpha: 0.3)
              : (isDark ? CoSpendColors.darkBorder : CoSpendColors.borderLight),
          width: isOver ? 1.2 : 0.8,
        ),
        boxShadow: isDark ? null : CoSpendShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: icon + name + amounts
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: onTapCategory,
                        borderRadius: BorderRadius.circular(10),
                        child: Row(
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: catItem.color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              alignment: Alignment.center,
                              child: Icon(catItem.icon, color: catItem.color, size: 22),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          catItem.label,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                            color: isDark
                                                ? Colors.white
                                                : CoSpendColors.prussianBlue,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(
                                        Icons.info_outline_rounded,
                                        size: 13,
                                        color: isDark
                                            ? CoSpendColors.darkTextMuted
                                            : CoSpendColors.textMuted,
                                      ),
                                    ],
                                  ),
                                  Text(
                                    'Monthly Limit • View details',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: isDark
                                          ? CoSpendColors.darkTextMuted
                                          : CoSpendColors.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Amount column
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (isOwner)
                          SizedBox(
                            width: 120,
                            child: TextField(
                              controller: controller,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                color: isDark
                                    ? Colors.white
                                    : CoSpendColors.prussianBlue,
                              ),
                              decoration: InputDecoration(
                                prefixText: 'Rs. ',
                                prefixStyle: TextStyle(
                                  color: isDark
                                      ? CoSpendColors.darkTextMuted
                                      : CoSpendColors.textMuted,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                                hintText: '0',
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                filled: true,
                                fillColor: isDark
                                    ? CoSpendColors.darkCanvas
                                    : const Color(0xFFF7F8FA),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: isDark
                                        ? CoSpendColors.darkBorder
                                        : const Color(0x1F0A2542),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: CoSpendColors.jadeGreen,
                                    width: 1.5,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: isDark
                                        ? CoSpendColors.darkBorder
                                        : const Color(0x1F0A2542),
                                  ),
                                ),
                              ),
                              onChanged: (_) => onAmountChanged(),
                            ),
                          )
                        else ...[
                          Text(
                            catBudgetPaisa > 0
                                ? Money.format(spentPaisa)
                                : Money.format(spentPaisa),
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              letterSpacing: -0.3,
                              color: isOver
                                  ? CoSpendColors.alertRed
                                  : (isDark
                                      ? Colors.white
                                      : CoSpendColors.prussianBlue),
                            ),
                          ),
                          if (catBudgetPaisa > 0)
                            Text(
                              'of ${Money.format(catBudgetPaisa)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? CoSpendColors.darkTextMuted
                                    : CoSpendColors.textMuted,
                              ),
                            ),
                        ],
                      ],
                    ),
                  ],
                ),

                if (isOwner) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _QuickChip(
                        label: '+1,000',
                        onTap: () => onAddAmount(1000),
                        isDark: isDark,
                      ),
                      const SizedBox(width: 6),
                      _QuickChip(
                        label: '+5,000',
                        onTap: () => onAddAmount(5000),
                        isDark: isDark,
                      ),
                      const SizedBox(width: 6),
                      _QuickChip(
                        label: '+10,000',
                        onTap: () => onAddAmount(10000),
                        isDark: isDark,
                      ),
                    ],
                  ),
                ],

                if (catBudgetPaisa > 0) ...[
                  const SizedBox(height: 12),
                  // Progress bar
                  ClipRRect(
                    borderRadius: CoSpendRadii.pillRadius,
                    child: Stack(
                      children: [
                        Container(
                          height: 7,
                          color: isDark
                              ? CoSpendColors.darkBorder
                              : const Color(0xFFEEF2F7),
                        ),
                        TweenAnimationBuilder<double>(
                          duration: const Duration(milliseconds: 600),
                          curve: Curves.easeOutCubic,
                          tween: Tween<double>(begin: 0, end: pct / 100.0),
                          builder: (context, value, _) => FractionallySizedBox(
                            widthFactor: value,
                            child: Container(
                              height: 7,
                              decoration: BoxDecoration(
                                color: progressColor,
                                borderRadius: CoSpendRadii.pillRadius,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isOver
                            ? 'OVER BUDGET'
                            : '${pct.toStringAsFixed(0)}% CONSUMED',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                          color: progressColor,
                        ),
                      ),
                      Text(
                        isOver
                            ? '+${Money.format(-remaining)}'
                            : '${Money.format(remaining)} LEFT',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isOver
                              ? CoSpendColors.alertRed
                              : (isDark
                                  ? CoSpendColors.darkTextMuted
                                  : CoSpendColors.textMuted),
                        ),
                      ),
                    ],
                  ),
                ],

                // Member quotas expand section
                if (isOwner && members.isNotEmpty && catBudgetPaisa > 0) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: onToggleExpand,
                    child: Row(
                      children: [
                        Text(
                          isExpanded
                              ? 'Hide member quotas'
                              : 'Set member quotas',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: CoSpendColors.jadeGreen,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          isExpanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          size: 16,
                          color: CoSpendColors.jadeGreen,
                        ),
                      ],
                    ),
                  ),
                  if (isExpanded) ...[
                    const SizedBox(height: 10),
                    ...members.map((member) {
                      final ctrl =
                          memberControllers[member.id] ??
                              TextEditingController();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor:
                                  CoSpendColors.jadeGreen.withValues(alpha: 0.2),
                              child: Text(
                                member.name.substring(0, 1).toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: CoSpendColors.jadeGreen,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                member.name,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? Colors.white
                                      : CoSpendColors.prussianBlue,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 110,
                              child: TextField(
                                controller: ctrl,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                textAlign: TextAlign.end,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: isDark
                                      ? Colors.white
                                      : CoSpendColors.prussianBlue,
                                ),
                                decoration: InputDecoration(
                                  prefixText: 'Rs. ',
                                  prefixStyle: TextStyle(
                                    color: isDark
                                        ? CoSpendColors.darkTextMuted
                                        : CoSpendColors.textMuted,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  hintText: '0',
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                  filled: true,
                                  fillColor: isDark
                                      ? CoSpendColors.darkCanvas
                                      : const Color(0xFFF7F8FA),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: isDark
                                          ? CoSpendColors.darkBorder
                                          : const Color(0x1F0A2542),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                      color: CoSpendColors.jadeGreen,
                                      width: 1.5,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: isDark
                                          ? CoSpendColors.darkBorder
                                          : const Color(0x1F0A2542),
                                    ),
                                  ),
                                ),
                                onChanged: (_) => onAmountChanged(),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    TextButton.icon(
                      onPressed: onSplitEqually,
                      icon: const Icon(
                        Icons.call_split_rounded,
                        size: 16,
                        color: CoSpendColors.jadeGreen,
                      ),
                      label: const Text(
                        'Split equally',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: CoSpendColors.jadeGreen,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick Amount Chip
// ─────────────────────────────────────────────────────────────────────────────

class _QuickChip extends StatelessWidget {
  const _QuickChip({
    required this.label,
    required this.onTap,
    required this.isDark,
  });

  final String label;
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: CoSpendColors.jadeGreen.withValues(alpha: 0.1),
          borderRadius: CoSpendRadii.pillRadius,
          border: Border.all(
            color: CoSpendColors.jadeGreen.withValues(alpha: 0.25),
            width: 0.8,
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: CoSpendColors.jadeGreen,
          ),
        ),
      ),
    );
  }
}
