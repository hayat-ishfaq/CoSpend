import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/services/notification_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../auth/presentation/providers/session_provider.dart';
import '../../../household/presentation/providers/notification_providers.dart';
import '../../../household/presentation/widgets/notifications_sheet.dart';

/// Root scaffold for the authenticated area: a 4-tab bottom navigation
/// (Home / Expenses / Budgets / More) with integrated inside/outside notification broadcasting.
class AppShellScreen extends ConsumerStatefulWidget {
  const AppShellScreen({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShellScreen> createState() => _AppShellScreenState();
}

class _AppShellScreenState extends ConsumerState<AppShellScreen> {
  final Set<String> _suppressedNotificationIds = {};
  bool _isInitialSnapshot = true;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentUserId = ref.watch(sessionProvider).value?.user?.id ?? '';

    // Global listener for new flatmate activity notifications (inside & outside the app)
    ref.listen(householdNotificationsProvider, (previous, next) {
      final list = next.value;
      if (list == null || list.isEmpty) return;

      // 1. Initial snapshot on login or app launch:
      // Seed all historical notifications as already known and suppressed.
      // Past notifications must NEVER trigger toasts or system tray alerts upon login.
      if (_isInitialSnapshot || previous?.value == null) {
        _isInitialSnapshot = false;
        for (final item in list) {
          _suppressedNotificationIds.add(item.id);
          NotificationService.instance.markPresented(item.id);
        }
        return;
      }

      final previousIds =
          previous?.value?.map((n) => n.id).toSet() ?? <String>{};
      final locallyRead = ref.read(locallyReadNotificationIdsProvider);

      for (final item in list) {
        final isNew = !previousIds.contains(item.id);
        final wasSuppressed = _suppressedNotificationIds.contains(item.id);
        final isNotMine = item.payerId != currentUserId;
        final isAlreadyReadInCloud = item.readByUserIds.contains(currentUserId);
        final isLocallyRead = locallyRead.contains(item.id);
        final notPresentedYet = !NotificationService.instance.isPresented(
          item.id,
        );

        // Only trigger alerts for genuinely NEW events occurring while actively using the app,
        // and only if the user hasn't already seen or read them.
        if (isNew &&
            !wasSuppressed &&
            isNotMine &&
            !isAlreadyReadInCloud &&
            !isLocallyRead &&
            notPresentedYet) {
          _suppressedNotificationIds.add(item.id);
          NotificationService.instance.markPresented(item.id);

          // 1. Outside the app: display system notification in Android/iOS notification tray
          NotificationService.instance.showNotification(
            notificationId: item.id,
            title: item.title,
            body: item.body,
          );

          // 2. Inside the app: display rich floating banner toast with one-tap sheet opener
          if (mounted) {
            showNotificationToast(
              context,
              title: item.title,
              body: item.body,
              onTap: () {
                // When tapped, mark as read immediately so it never notifies again
                ref
                    .read(notificationActionsProvider.notifier)
                    .markAsRead(item.id);
                NotificationsSheet.show(context);
              },
            );
          }
        }
      }
    });

    return Scaffold(
      body: widget.navigationShell,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF071A2E) : CoSpendColors.white,
          border: Border(
            top: BorderSide(
              color: isDark
                  ? CoSpendColors.darkBorder
                  : CoSpendColors.borderLight,
              width: 0.8,
            ),
          ),
          boxShadow: isDark ? null : CoSpendShadows.navBar,
        ),
        child: SafeArea(
          top: false,
          child: NavigationBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            shadowColor: Colors.transparent,
            selectedIndex: widget.navigationShell.currentIndex,
            onDestinationSelected: (index) {
              HapticFeedback.selectionClick();
              widget.navigationShell.goBranch(
                index,
                initialLocation: index == widget.navigationShell.currentIndex,
              );
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long_rounded),
                label: 'Expenses',
              ),
              NavigationDestination(
                icon: Icon(Icons.donut_large_outlined),
                selectedIcon: Icon(Icons.donut_large_rounded),
                label: 'Budgets',
              ),
              NavigationDestination(
                icon: Icon(Icons.grid_view_outlined),
                selectedIcon: Icon(Icons.grid_view_rounded),
                label: 'More',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
