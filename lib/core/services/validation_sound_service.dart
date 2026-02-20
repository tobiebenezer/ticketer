import 'package:audioplayers/audioplayers.dart';
import 'package:myapp/core/services/app_settings_service.dart';
import 'package:myapp/core/services/offline_validation_service.dart';

class ValidationSoundService {
  ValidationSoundService._();

  static final ValidationSoundService instance = ValidationSoundService._();

  final AudioPlayer _player = AudioPlayer(playerId: 'validation-sounds');
  final AppSettingsService _settings = AppSettingsService();
  DateTime? _lastPlayedAt;

  static const String _successAsset = 'assets/sounds/validation_success.mp3';
  static const String _failedAsset = 'assets/sounds/validation_failed.mp3';

  Future<void> playForStatus(ValidationStatus status) async {
    final isSuccess = status == ValidationStatus.valid;
    await _playAsset(isSuccess ? _successAsset : _failedAsset);
  }

  Future<void> _playAsset(String assetPath) async {
    final soundEnabled = await _settings.getValidationSoundEnabled();
    if (!soundEnabled) return;

    final now = DateTime.now();
    if (_lastPlayedAt != null &&
        now.difference(_lastPlayedAt!).inMilliseconds < 150) {
      return;
    }
    _lastPlayedAt = now;

    try {
      await _player.stop();
      await _playAssetWithFallback(assetPath);
    } catch (_) {
      // Ignore sound playback errors to keep validation flow non-blocking.
    }
  }

  Future<void> _playAssetWithFallback(String assetPath) async {
    try {
      await _player.play(AssetSource(assetPath), volume: 1.0);
      return;
    } catch (_) {
      final stripped = assetPath.startsWith('assets/')
          ? assetPath.substring('assets/'.length)
          : assetPath;
      await _player.play(AssetSource(stripped), volume: 1.0);
    }
  }
}
