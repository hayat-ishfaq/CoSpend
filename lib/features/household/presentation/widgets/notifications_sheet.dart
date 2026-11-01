import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/money.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../auth/presentation/providers/session_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../domain/household_notification.dart';
import '../providers/notification_providers.dart';

class NotificationsSheet extends ConsumerStatefulWidget {
  const NotificationsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const NotificationsSheet(),
    );
  }

  @override
  ConsumerState<NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends ConsumerState<NotificationsSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationActionsProvider.notifier).markAllAsRead();
    });
  }

  String _formatTimeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final notificationsAsync = ref.watch(householdNotificationsProvider);

    ref.listen<AsyncValue<List<HouseholdNotification>>>(
      householdNotificationsProvider,
      (prev, next) {
        if (next.hasValue && next.value != null && next.value!.isNotEmpty) {
          ref.read(notificationActionsProvider.notifier).markAllAsRead();
        }
      },
    );

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: isDark ? CoSpendColors.darkCard : CoSpendColors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: isDark
                    ? CoSpendColors.darkBorder
                    : CoSpendColors.border.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header with Jade Green tint circle
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 16, 14),
            child: Row(
              children: [
                const TintedIcon(
                  icon: Icons.notifications_active_rounded,
                  color: CoSpendColors.jadeGreen,
                  size: 20,
                  containerSize: 40,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Flat Activity & Alerts',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          letterSpacing: -0.3,
                          color: isDark ? Colors.white : CoSpendColors.prussianBlue,
                        ),
                      ),
                      Text(
                        'Recent spending updates from roommates',
                        style: TextStyle(
                          color: isDark ? CoSpendColors.darkTextMuted : CoSpendColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () {
                    ref.read(notificationActionsProvider.notifier).markAllAsRead();
                    showAppSnack(context, 'All notifications marked as read.');
                  },
                  child: const Text(
                    'Mark all read',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: CoSpendColors.jadeGreen,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: isDark ? CoSpendColors.darkBorder : CoSpendColors.borderLight,
          ),

          // Notification List
          Expanded(
            child: notificationsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(),
              ),
              error: (err, _) => Center(
                child: Text('Could not load notifications: $err'),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: CoSpendColors.prussianBlue.withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.notifications_none_rounded,
                              size: 32,
                              color: CoSpendColors.prussianBlue,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'All caught up!',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: isDark ? Colors.white : CoSpendColors.prussianBlue,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'When roommates log expenses or budget alerts trigger, you\'ll see them right here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: isDark ? CoSpendColors.darkTextMuted : CoSpendColors.textMuted,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final currentUserId = FirebaseAuth.instance.currentUser?.uid ??
                    ref.watch(currentUserProvider).value?.id ??
                    ref.watch(sessionProvider).value?.user?.id ?? '';
                final locallyRead = ref.watch(locallyReadNotificationIdsProvider);

                final displayItems = items
                    .where((n) => !n.isCreatedBy(currentUserId))
                    .toList();

                if (displayItems.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: CoSpendColors.prussianBlue.withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.notifications_none_rounded,
                              size: 32,
                              color: CoSpendColors.prussianBlue,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'All caught up!',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: isDark ? Colors.white : CoSpendColors.prussianBlue,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'When roommates log expenses or budget alerts trigger, you\'ll see them right here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: isDark ? CoSpendColors.darkTextMuted : CoSpendColors.textMuted,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: displayItems.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = displayItems[index];
                    final isUnread = !item.readByUserIds.contains(currentUserId) &&
                        !locallyRead.contains(item.id);

                    return InkWell(
                      borderRadius: CoSpendRadii.cardRadius,
                      onTap: () {
                        ref.read(notificationActionsProvider.notifier).markAsRead(item.id);
                        Navigator.of(context).pop();
                        if (item.category.toLowerCase().contains('settle')) {
                          context.push(Routes.settle);
                        } else {
                          context.push(Routes.expenses);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? CoSpendColors.darkCanvas : CoSpendColors.canvas,
                          borderRadius: CoSpendRadii.cardRadius,
                          border: Border.all(
                            color: isUnread
                                ? CoSpendColors.jadeGreen.withValues(alpha: 0.6)
                                : (isDark ? CoSpendColors.darkBorder : CoSpendColors.borderLight),
                            width: isUnread ? 1.4 : 1.0,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: CoSpendColors.jadeGreen.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              item.category.toLowerCase().contains('settle')
                                  ? Icons.swap_horiz_rounded
                                  : Icons.receipt_rounded,
                              size: 16,
                              color: CoSpendColors.jadeGreen,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              item.title,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 13.5,
                                                color: isDark ? Colors.white : CoSpendColors.prussianBlue,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (isUnread) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              width: 7,
                                              height: 7,
                                              decoration: const BoxDecoration(
                                                color: CoSpendColors.jadeGreen,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    Text(
                                      _formatTimeAgo(item.createdAt),
                                      style: TextStyle(
                                        color: isDark ? CoSpendColors.darkTextMuted : CoSpendColors.textSubtle,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  item.body,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: isDark ? CoSpendColors.darkTextMuted : CoSpendColors.textMuted,
                                    height: 1.3,
                                  ),
                                ),
                                if (item.amountPaisa > 0) ...[
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: CoSpendColors.jadeGreen.withValues(alpha: 0.1),
                                      borderRadius: CoSpendRadii.pillRadius,
                                    ),
                                    child: Text(
                                      Money.format(item.amountPaisa),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: CoSpendColors.jadeGreen,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
