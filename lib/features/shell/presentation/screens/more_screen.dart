import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/theme/theme_controller.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/app_avatar.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../auth/presentation/providers/session_provider.dart';
import '../../../household/presentation/providers/household_providers.dart';
import '../../../household/presentation/widgets/invite_members_sheet.dart';
import '../../../household/presentation/widgets/notification_bell_button.dart';

/// Settings / More tab — premium fintech style matching CoSpend design system.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  Future<void> _renameFlat(
    BuildContext context,
    WidgetRef ref,
    String householdId,
    String currentName,
  ) async {
    final household = ref.read(currentHouseholdProvider).value;
    final currentUserId = ref.read(sessionProvider).value?.user?.id;
    if (household == null || household.ownerId != currentUserId) {
      showAppSnack(
        context,
        'Only the flat owner (admin) can change the flat name.',
        error: true,
      );
      return;
    }

    final controller = TextEditingController(text: currentName);
    final formKey = GlobalKey<FormState>();

    final updated = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Rename Flat'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Flat name',
              hintText: 'e.g. Air University Hostel',
              border: OutlineInputBorder(),
            ),
            validator: Validators.flatName,
            autofocus: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(dialogCtx).pop(true);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (updated == true && context.mounted) {
      await ref.read(householdActionsProvider.notifier).rename(
            householdId: householdId,
            name: controller.text.trim(),
          );
      if (context.mounted) {
        showAppSnack(context, 'Flat renamed to "${controller.text.trim()}".');
      }
    }
  }

  Future<void> _leaveFlat(BuildContext context, WidgetRef ref) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Leave flat?',
      message:
          'You will be removed from this flat and need an invite code to join again.',
      confirmLabel: 'Leave',
      destructive: true,
    );
    if (confirmed == true && context.mounted) {
      await ref.read(householdActionsProvider.notifier).leave();
      if (context.mounted) showAppSnack(context, 'You left the flat.');
    }
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Sign out?',
      message: 'You can sign back in anytime — your flat and expenses stay put.',
      confirmLabel: 'Sign out',
    );
    if (confirmed == true) {
      await ref.read(authActionsProvider.notifier).signOut();
    }
  }


  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final session = ref.read(sessionProvider).value;
    final user = session?.user;
    if (user == null) return;
    final household = ref.read(currentHouseholdProvider).value;

    // Step 1: warn the user
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete account permanently?',
      message:
          'This will remove your profile, data, and access to CoSpend. This action cannot be undone.',
      confirmLabel: 'Continue',
      destructive: true,
    );
    if (confirmed != true || !context.mounted) return;

    // Step 2: ask for password to re-authenticate
    final passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final passwordConfirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm your password'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: passwordController,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Password',
              border: OutlineInputBorder(),
            ),
            validator: (v) =>
                (v == null || v.isEmpty) ? 'Please enter your password.' : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: CoSpendColors.alertRed,
            ),
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(ctx).pop(true);
              }
            },
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
    if (passwordConfirmed != true || !context.mounted) return;

    try {
      await ref.read(authActionsProvider.notifier).deleteAccount(
            uid: user.id,
            email: user.email,
            password: passwordController.text,
            householdId: household?.id,
          );
    } catch (e) {
      if (context.mounted) {
        showAppSnack(context, e.toString(), error: true);
      }
    }
  }

  Future<void> _launchUrl(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (context.mounted) {
      showAppSnack(context, 'Could not open link.', error: true);
    }
  }
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    final household = ref.watch(currentHouseholdProvider).value;
    final themeMode = ref.watch(themeModeProvider).value ?? ThemeMode.system;

    final user = session?.user;
    final currentUser = ref.watch(currentUserProvider).value ?? user;
    final isOwner = household != null && household.ownerId == currentUser?.id;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? CoSpendColors.darkCanvas : CoSpendColors.canvas,
      appBar: AppBar(
        backgroundColor: isDark ? CoSpendColors.darkCanvas : CoSpendColors.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(
          'MORE',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.8,
            color: isDark ? Colors.white : CoSpendColors.prussianBlue,
          ),
        ),
        actions: [
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // ── Profile Card ──────────────────────────────────────────────
          GestureDetector(
            onTap: () => context.push(Routes.profile),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [CoSpendColors.prussianBlue, Color(0xFF133863)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: CoSpendRadii.cardLargeRadius,
                boxShadow: [
                  BoxShadow(
                    color: CoSpendColors.prussianBlue.withValues(alpha: 0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Avatar with jade ring
                  Container(
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: CoSpendColors.jadeGreen,
                        width: 2.5,
                      ),
                    ),
                    child: AppAvatar(
                      name: user?.name ?? '',
                      photoUrl: user?.photoUrl,
                      size: 52,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                user?.name ?? 'CoSpend Member',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 17,
                                  letterSpacing: -0.3,
                                  color: Colors.white,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isOwner) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      CoSpendColors.jadeGreen.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: CoSpendColors.jadeGreen
                                        .withValues(alpha: 0.5),
                                    width: 0.8,
                                  ),
                                ),
                                child: const Text(
                                  'OWNER',
                                  style: TextStyle(
                                    color: CoSpendColors.jadeGreen,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 9,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          user?.email ?? '',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (household != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.home_rounded,
                                size: 12,
                                color: Colors.white.withValues(alpha: 0.6),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                household.name,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white.withValues(alpha: 0.75),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.edit_outlined,
                    size: 18,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── Flat Settings ─────────────────────────────────────────────
          if (household != null) ...[
            _SectionHeader(label: 'FLAT SETTINGS', isDark: isDark),
            const SizedBox(height: 8),
            _MenuGroup(
              isDark: isDark,
              items: [
                if (isOwner)
                  _MenuItem(
                    icon: Icons.edit_rounded,
                    iconColor: CoSpendColors.prussianBlue,
                    title: 'Rename flat',
                    subtitle: household.name,
                    onTap: () => _renameFlat(
                      context,
                      ref,
                      household.id,
                      household.name,
                    ),
                    trailing: Icons.edit_outlined,
                    isDark: isDark,
                  ),
                _MenuItem(
                  icon: Icons.donut_large_rounded,
                  iconColor: const Color(0xFF8B5CF6),
                  title: 'Category Budgets',
                  subtitle: household.effectiveTotalBudgetPaisa > 0
                      ? '${Money.format(household.effectiveTotalBudgetPaisa)} monthly target'
                      : isOwner
                          ? 'Set category spending limits'
                          : 'View limits (managed by owner)',
                  onTap: () => context.push(Routes.categoryBudgets),
                  isDark: isDark,
                ),
                _MenuItem(
                  icon: Icons.swap_horiz_rounded,
                  iconColor: const Color(0xFF0EA5E9),
                  title: 'Settle up',
                  subtitle: 'See who owes whom and record payments',
                  onTap: () => context.push(Routes.settle),
                  isDark: isDark,
                ),
                _MenuItem(
                  icon: Icons.group_add_rounded,
                  iconColor: const Color(0xFF0EA5E9),
                  title: 'Join another flat',
                  subtitle: 'Enter an invite code from roommates',
                  onTap: () => context.push(Routes.joinFlat),
                  isDark: isDark,
                ),
                _MenuItem(
                  icon: Icons.share_rounded,
                  iconColor: CoSpendColors.jadeGreen,
                  title: 'Invite flatmates',
                  subtitle: 'Code: ${household.inviteCode}',
                  onTap: () => InviteMembersSheet.show(context, household),
                  isDark: isDark,
                ),
                _MenuItem(
                  icon: Icons.settings_rounded,
                  iconColor: const Color(0xFFF59E0B),
                  title: 'Household settings',
                  subtitle: 'Members, permissions & preferences',
                  onTap: () => context.push(Routes.householdSettings),
                  isDark: isDark,
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // ── Appearance ────────────────────────────────────────────────
          _SectionHeader(label: 'APPEARANCE', isDark: isDark),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: isDark ? CoSpendColors.darkCard : CoSpendColors.white,
              borderRadius: CoSpendRadii.cardRadius,
              border: Border.all(
                color: isDark ? CoSpendColors.darkBorder : CoSpendColors.borderLight,
                width: 0.8,
              ),
              boxShadow: isDark ? null : CoSpendShadows.card,
            ),
            child: Column(
              children: [
                for (int i = 0; i < ThemeMode.values.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                      color: isDark
                          ? CoSpendColors.darkBorder
                          : const Color(0x0F0A2542),
                    ),
                  InkWell(
                    onTap: () => ref
                        .read(themeModeProvider.notifier)
                        .setMode(ThemeMode.values[i]),
                    borderRadius: i == 0
                        ? const BorderRadius.vertical(top: Radius.circular(12))
                        : i == ThemeMode.values.length - 1
                            ? const BorderRadius.vertical(
                                bottom: Radius.circular(12))
                            : BorderRadius.zero,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          Icon(
                            _themeModeIcon(ThemeMode.values[i]),
                            size: 20,
                            color: themeMode == ThemeMode.values[i]
                                ? CoSpendColors.jadeGreen
                                : (isDark
                                    ? CoSpendColors.darkTextMuted
                                    : CoSpendColors.textMuted),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              _themeModeLabel(ThemeMode.values[i]),
                              style: TextStyle(
                                fontWeight: themeMode == ThemeMode.values[i]
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                fontSize: 14,
                                color: themeMode == ThemeMode.values[i]
                                    ? (isDark
                                        ? Colors.white
                                        : CoSpendColors.prussianBlue)
                                    : (isDark
                                        ? Colors.white70
                                        : const Color(0xFF374151)),
                              ),
                            ),
                          ),
                          _RadioDot(
                            selected: themeMode == ThemeMode.values[i],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Help & Support ────────────────────────────────────────────
          _SectionHeader(label: 'HELP & SUPPORT', isDark: isDark),
          const SizedBox(height: 8),
          _MenuGroup(
            isDark: isDark,
            items: [
              _MenuItem(
                icon: Icons.help_outline_rounded,
                iconColor: const Color(0xFF0EA5E9),
                title: 'Help & FAQ',
                subtitle: 'Get answers to common questions',
                onTap: () => context.push(Routes.helpFaq),
                isDark: isDark,
              ),
              _MenuItem(
                icon: Icons.mail_outline_rounded,
                iconColor: CoSpendColors.jadeGreen,
                title: 'Contact support',
                subtitle: 'Reach out to our team',
                onTap: () => context.push(Routes.contactSupport),
                isDark: isDark,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Account ───────────────────────────────────────────────────
          _SectionHeader(label: 'ACCOUNT', isDark: isDark),
          const SizedBox(height: 8),
          _MenuGroup(
            isDark: isDark,
            items: [
              _MenuItem(
                icon: Icons.person_outline_rounded,
                iconColor: CoSpendColors.prussianBlue,
                title: 'Edit profile',
                subtitle: 'Update name, photo & phone number',
                onTap: () => context.push(Routes.profile),
                isDark: isDark,
              ),
              if (household != null)
                _MenuItem(
                  icon: Icons.exit_to_app_rounded,
                  iconColor: CoSpendColors.warningAmber,
                  title: 'Leave flat',
                  subtitle: 'Remove yourself from ${household.name}',
                  onTap: () => _leaveFlat(context, ref),
                  titleColor: CoSpendColors.warningAmber,
                  isDark: isDark,
                ),
              _MenuItem(
                icon: Icons.power_settings_new_rounded,
                iconColor: CoSpendColors.alertRed,
                title: 'Sign out',
                subtitle: 'Your data stays safely stored',
                onTap: () => _confirmSignOut(context, ref),
                titleColor: CoSpendColors.alertRed,
                isDark: isDark,
              ),
            ],
          ),
          const SizedBox(height: 28),

          // ── Footer ────────────────────────────────────────────────────
          Center(
            child: Column(
              children: [
                // App logo / branding pill
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? CoSpendColors.darkCardElevated
                        : CoSpendColors.surfaceMuted,
                    borderRadius: CoSpendRadii.pillRadius,
                    border: Border.all(
                      color: isDark
                          ? CoSpendColors.darkBorder
                          : CoSpendColors.borderLight,
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              CoSpendColors.jadeGreen,
                              CoSpendColors.prussianBlue,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.home_rounded,
                          size: 13,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${AppConstants.appName}  ·  v1.0.0',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? CoSpendColors.darkTextMuted
                              : CoSpendColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Made with ❤️ for flatmates',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark
                        ? CoSpendColors.darkTextMuted
                        : CoSpendColors.textSubtle,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _themeModeLabel(ThemeMode mode) => switch (mode) {
        ThemeMode.system => 'System default',
        ThemeMode.light => 'Light mode',
        ThemeMode.dark => 'Dark mode',
      };

  IconData _themeModeIcon(ThemeMode mode) => switch (mode) {
        ThemeMode.system => Icons.brightness_auto_rounded,
        ThemeMode.light => Icons.light_mode_rounded,
        ThemeMode.dark => Icons.dark_mode_rounded,
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// Section Header
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.isDark});

  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: isDark ? CoSpendColors.darkTextMuted : CoSpendColors.textMuted,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Menu Group (white card with dividers)
// ─────────────────────────────────────────────────────────────────────────────

class _MenuGroup extends StatelessWidget {
  const _MenuGroup({required this.isDark, required this.items});

  final bool isDark;
  final List<_MenuItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? CoSpendColors.darkCard : CoSpendColors.white,
        borderRadius: CoSpendRadii.cardRadius,
        border: Border.all(
          color: isDark ? CoSpendColors.darkBorder : CoSpendColors.borderLight,
          width: 0.8,
        ),
        boxShadow: isDark ? null : CoSpendShadows.card,
      ),
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: 56,
                endIndent: 16,
                color: isDark
                    ? CoSpendColors.darkBorder
                    : const Color(0x0F0A2542),
              ),
            items[i],
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Menu Item Row
// ─────────────────────────────────────────────────────────────────────────────

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.isDark,
    this.trailing,
    this.titleColor,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isDark;
  final IconData? trailing;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: CoSpendRadii.cardRadius,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            // Icon container
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 19, color: iconColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: titleColor ??
                          (isDark ? Colors.white : CoSpendColors.prussianBlue),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? CoSpendColors.darkTextMuted
                          : CoSpendColors.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              trailing ?? Icons.chevron_right_rounded,
              size: 18,
              color: isDark
                  ? CoSpendColors.darkTextMuted
                  : const Color(0xFFCBD5E1),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Radio Dot (for theme selection)
// ─────────────────────────────────────────────────────────────────────────────

class _RadioDot extends StatelessWidget {
  const _RadioDot({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? CoSpendColors.jadeGreen : const Color(0xFFD1D5DB),
          width: 2,
        ),
      ),
      alignment: Alignment.center,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: selected ? 10 : 0,
        height: selected ? 10 : 0,
        decoration: const BoxDecoration(
          color: CoSpendColors.jadeGreen,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}