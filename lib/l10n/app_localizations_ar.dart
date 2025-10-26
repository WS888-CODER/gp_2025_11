// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get settingsTitle => 'الإعدادات';

  @override
  String get generalSettingsSection => 'الإعدادات العامة';

  @override
  String get languageOption => 'اللغة';

  @override
  String get themeOption => 'السمة';

  @override
  String get notificationsOption => 'الإشعارات';

  @override
  String get manageAlertsSubtitle => 'إدارة التنبيهات والإشعارات';

  @override
  String get accountSecuritySection => 'الحساب والأمان';

  @override
  String get changePasswordOption => 'تغيير كلمة المرور';

  @override
  String get resetPasswordSubtitle => 'إعادة تعيين كلمة المرور';

  @override
  String get accountVerificationStatus => 'حالة توثيق الحساب';

  @override
  String get viewOnlyText => 'للعرض فقط';

  @override
  String get myAccountDetailsSection => 'تفاصيل حسابي';

  @override
  String get fullNameLabel => 'الاسم الكامل';

  @override
  String get companyNameLabel => 'اسم الشركة';

  @override
  String get registeredEmailLabel => 'البريد الإلكتروني المسجل';

  @override
  String get contactPhoneLabel => 'رقم الاتصال';

  @override
  String get logoutOption => 'تسجيل الخروج';

  @override
  String switchLanguage(Object targetLang) {
    return 'تبديل اللغة إلى $targetLang';
  }

  @override
  String currentLanguage(Object langName) {
    return 'الحالية: $langName';
  }
}
