import 'package:shared_preferences/shared_preferences.dart';

/// AppSettingsService - System-wide application settings
///
/// Manages user preferences that affect app behavior across all screens.
class AppSettingsService {
  static const String _kPreferOfflineSales = 'prefer_offline_sales';
  static const String _kPreferOfflineValidation = 'prefer_offline_validation';
  static const String _kAutoSyncEnabled = 'auto_sync_enabled';
  static const String _kFastCheckoutMode = 'fast_checkout_mode';
  static const String _kAutoPrintEnabled = 'auto_print_enabled';
  static const String _kValidationPopupTimeoutSeconds =
      'validation_popup_timeout_seconds';
  static const String _kValidationSoundEnabled = 'validation_sound_enabled';
  static const String _kPrinterDelayMs = 'printer_delay_ms';

  /// Get whether to prefer offline sales over API calls
  /// Default: true (offline-first)
  Future<bool> getPreferOfflineSales() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kPreferOfflineSales) ?? true;
  }

  /// Set offline sales preference
  Future<void> setPreferOfflineSales(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPreferOfflineSales, value);
  }

  /// Get whether to prefer offline validation
  /// Default: true (offline-first)
  Future<bool> getPreferOfflineValidation() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kPreferOfflineValidation) ?? true;
  }

  /// Set offline validation preference
  Future<void> setPreferOfflineValidation(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPreferOfflineValidation, value);
  }

  /// Get whether auto-sync is enabled
  /// Default: true
  Future<bool> getAutoSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kAutoSyncEnabled) ?? true;
  }

  /// Set auto-sync preference
  Future<void> setAutoSyncEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoSyncEnabled, value);
  }

  // Auto-Print Tickets
  Future<bool> getAutoPrintEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kAutoPrintEnabled) ?? true; // Default: enabled
  }

  Future<void> setAutoPrintEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoPrintEnabled, enabled);
  }

  /// Get validation popup timeout in seconds
  /// Default: 5 seconds
  Future<int> getValidationPopupTimeoutSeconds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kValidationPopupTimeoutSeconds) ?? 5;
  }

  /// Set validation popup timeout in seconds
  Future<void> setValidationPopupTimeoutSeconds(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kValidationPopupTimeoutSeconds, value);
  }

  /// Get whether validation sounds are enabled
  /// Default: true
  Future<bool> getValidationSoundEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kValidationSoundEnabled) ?? true;
  }

  /// Set validation sounds preference
  Future<void> setValidationSoundEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kValidationSoundEnabled, value);
  }

  /// Get printer delay between tickets in milliseconds
  /// Default: 1500ms (1.5 seconds)
  Future<int> getPrinterDelayMs() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kPrinterDelayMs) ?? 1500;
  }

  /// Set printer delay between tickets in milliseconds
  Future<void> setPrinterDelayMs(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPrinterDelayMs, value);
  }

  /// Get whether fast checkout mode is enabled
  Future<bool> getFastCheckoutMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kFastCheckoutMode) ?? false;
  }

  /// Set fast checkout mode preference
  Future<void> setFastCheckoutMode(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kFastCheckoutMode, enabled);
  }

  /// Get all settings as a map
  Future<Map<String, dynamic>> getAllSettings() async {
    return {
      'prefer_offline_sales': await getPreferOfflineSales(),
      'prefer_offline_validation': await getPreferOfflineValidation(),
      'auto_sync_enabled': await getAutoSyncEnabled(),
      'auto_print_enabled': await getAutoPrintEnabled(),
      'fast_checkout_mode': await getFastCheckoutMode(),
      'validation_popup_timeout_seconds':
          await getValidationPopupTimeoutSeconds(),
      'validation_sound_enabled': await getValidationSoundEnabled(),
      'printer_delay_ms': await getPrinterDelayMs(),
    };
  }

  /// Reset all settings to defaults
  Future<void> resetToDefaults() async {
    await setPreferOfflineSales(true);
    await setPreferOfflineValidation(true);
    await setAutoSyncEnabled(true);
    await setAutoPrintEnabled(true);
    await setFastCheckoutMode(false);
    await setValidationPopupTimeoutSeconds(5);
    await setValidationSoundEnabled(true);
    await setPrinterDelayMs(1500);
  }
}
