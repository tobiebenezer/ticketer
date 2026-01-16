import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';

/// Device information for registration
class DeviceInfo {
  final String uid;
  final String type;
  final String model;
  final String osVersion;

  DeviceInfo({
    required this.uid,
    required this.type,
    required this.model,
    required this.osVersion,
  });

  Map<String, dynamic> toJson() => {
    'device_uid': uid,
    'device_type': type,
    'device_model': model,
    'os_version': osVersion,
  };
}

/// Utility to get device information
class DeviceInfoUtil {
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  /// Get device information for registration
  static Future<DeviceInfo> getDeviceInfo() async {
    if (Platform.isAndroid) {
      final androidInfo = await _deviceInfo.androidInfo;
      return DeviceInfo(
        uid: androidInfo.id, // Android ID
        type: 'android',
        model: '${androidInfo.manufacturer} ${androidInfo.model}',
        osVersion: 'Android ${androidInfo.version.release}',
      );
    } else if (Platform.isIOS) {
      final iosInfo = await _deviceInfo.iosInfo;
      return DeviceInfo(
        uid: iosInfo.identifierForVendor ?? 'unknown', // iOS vendor ID
        type: 'ios',
        model: '${iosInfo.name} ${iosInfo.model}',
        osVersion: 'iOS ${iosInfo.systemVersion}',
      );
    } else {
      // Fallback for other platforms
      return DeviceInfo(
        uid: 'unknown',
        type: Platform.operatingSystem,
        model: 'unknown',
        osVersion: Platform.operatingSystemVersion,
      );
    }
  }
}
