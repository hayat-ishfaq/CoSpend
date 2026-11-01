/// Global app-wide constants.
///
/// The product name lives here so "FlatSplit" can be renamed in one place.
abstract final class AppConstants {
  static const String appName = 'CoSpend';
  static const String tagline = 'Co-living budgets, perfectly tracked.';

  /// ISO currency code used for new households.
  static const String defaultCurrency = 'PKR';

  /// Invite codes look like `FLAT-7K29`.
  static const String invitePrefix = 'FLAT-';
  static const int inviteCodeLength = 4;

  static const int minPasswordLength = 8;
  static const int maxNameLength = 60;
  static const int maxFlatNameLength = 50;
  static const int maxDescriptionLength = 120;

  /// Practical upper bound for a flat; larger groups get an explicit warning.
  static const int maxHouseholdMembers = 10;

  static const String supportEmail = 'support@cospend.app';
  static const String supportGithubUrl =
      'https://github.com/hayat-ishfaq/expensetrack/issues';

  /// Legal links — displayed in Help & Support and on the signup screen.
  static const String privacyPolicyUrl =
      'https://cospend.app/privacy';
  static const String termsOfServiceUrl =
      'https://cospend.app/terms';
}
