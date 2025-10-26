// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get settingsTitle => 'Settings';

  @override
  String get generalSettingsSection => 'General Settings';

  @override
  String get languageOption => 'Language';

  @override
  String get themeOption => 'Theme';

  @override
  String get notificationsOption => 'Notifications';

  @override
  String get manageAlertsSubtitle => 'Manage your alerts and pushes';

  @override
  String get accountSecuritySection => 'Account & Security';

  @override
  String get changePasswordOption => 'Change Password';

  @override
  String get resetPasswordSubtitle => 'Reset your password';

  @override
  String get accountVerificationStatus => 'Account Verification Status';

  @override
  String get viewOnlyText => 'Edits Account Information';

  @override
  String get myAccountDetailsSection => 'My Account Details';

  @override
  String get fullNameLabel => 'Full Name';

  @override
  String get companyNameLabel => 'Company Name';

  @override
  String get registeredEmailLabel => 'Registered Email';

  @override
  String get contactPhoneLabel => 'Contact Phone';

  @override
  String get logoutOption => 'Logout';

  @override
  String switchLanguage(Object targetLang) {
    return 'Switch Language to $targetLang';
  }

  @override
  String currentLanguage(Object langName) {
    return 'Current: $langName';
  }
}
